!
!     ******************************************************************
!     *                                                                *
!     * File:          verifydCfdx.f90                                 *
!     * Author:        Andre C. Marta, C.A.(Sandy) Mader               *
!     * Starting date: 01-15-2007                                      *
!     * Last modified: 08-18-2008                                      *
!     *                                                                *
!     ******************************************************************
!
subroutine verifydSdw(level)
!
!     ******************************************************************
!     *                                                                *
!     * Compute all entries in dSdw (partial) using the automatically  *
!     * differentiated routines generated by Tapenade and compare      *
!     * them to the finite-difference results using the modified       *
!     * force routine. This is only executed in debug mode.            *
!     *                                                                *
!     ******************************************************************
!
      use adjointpetsc        !djdw
      use adjointVars         !nCellsGlobal
      use blockPointers
      use cgnsGrid            ! cgnsDoms
      use communication       ! procHalo(currentLevel)%nProcSend, myID
      use inputPhysics        ! equations
      use flowVarRefState     ! nw
      use inputDiscretization ! spaceDiscr, useCompactDiss
      use iteration           ! overset, currentLevel
      use inputTimeSpectral   ! nTimeIntervalsSpectral
      use section
      use monitor             ! monLoc, MonGlob, nMonSum
      use bcTypes             !imin,imax,jmin,jmax,kmin,kmax
      use mdDataLocal
      use mdData
      implicit none
!
!     Subroutine arguments.
!
      integer(kind=intType), intent(in) :: level
!
!     Local variables.
!
      integer(kind=intType) :: discr, nHalo, sps
      integer(kind=intType) :: modFamID,ii,famID=0,startind,endind
      integer(kind=intType) :: icell, jcell, kcell, mm, nn, m, n
      !integer(kind=intType) :: ii, jj, kk, i1, j1, k1, i2, j2, k2

      integer(kind=intType) ::  i2Beg,  i2End,  j2Beg,  j2End
      integer(kind=intType) :: iiBeg, iiEnd, jjBeg, jjEnd
      integer(kind=intType) :: i,j,k,l

      logical :: fineGrid,correctForK, exchangeTurb
      integer(kind=intType)::liftIndex

      real(kind=realType), dimension(:,:,:,:), allocatable :: xAdj,xAdjB
      real(kind=realType), dimension(:,:,:,:), allocatable :: wAdj,wAdjB
      real(kind=realType), dimension(:,:,:), allocatable :: pAdj

      real(kind=realType), dimension(:,:),allocatable :: forceLoc,forcelocb,forcelocp,forcelocm

      real(kind=realType) :: alphaAdj, betaAdj,MachAdj,machCoefAdj
      real(kind=realType) :: alphaAdjb, betaAdjb,MachAdjb,machCoefAdjb
      REAL(KIND=REALTYPE) :: prefAdj, rhorefAdj,pInfCorrAdj
      REAL(KIND=REALTYPE) :: pinfdimAdj, rhoinfdimAdj
      REAL(KIND=REALTYPE) :: rhoinfAdj, pinfAdj
      REAL(KIND=REALTYPE) :: murefAdj, timerefAdj


      real(kind=realType) :: factI, factJ, factK, tmp

      integer(kind=intType), dimension(0:nProc-1) :: offsetRecv

      real(kind=realType), dimension(4) :: time
      real(kind=realType)               :: timeAdj, timeFD

      ! > derivative output

      real(kind=realType), dimension(:,:,:,:,:,:), allocatable ::dSdwAD, &
           dSDwFD,dSdwer
!      real(kind=realType), dimension(:,:,:,:,:), allocatable :: dCLfd, &
!           dCDfd,dCmxfd
!      real(kind=realType), dimension(:,:,:,:,:), allocatable :: dCLer, &
!           dCDer,dCmxer

      real(kind=realType), parameter :: deltaw = 1.e-8_realType

      real(kind=realType) :: wAdjRef, wref,test

      real(kind=realType), dimension(:,:,:), pointer :: norm
      real(kind=realType), dimension(:,:,:),allocatable:: normAdj
      real(kind=realType), dimension(3) :: refPoint
      real(kind=realType) :: yplusMax

      logical :: contributeToForce, viscousSubface,secondHalo,righthanded

      integer :: ierr,nmonsum1,nmonsum2,idxmgb,idxres,idxsurf

      character(len=2*maxStringLen) :: errorMessage

      ! dJ/dw row block
      
      real(kind=realType), dimension(nw) :: dJdWlocal
	

!File Parameters
      integer :: unit = 8,ierror
      character(len = 10)::outfile
      
      outfile = "dSdw.txt"
      
      open (UNIT=unit,File=outfile,status='replace',action='write',iostat=ierror)
      if(ierror /= 0)                        &
           call terminate("verifydSdw", &
           "Something wrong when &
           &calling open")
!
!     ******************************************************************
!     *                                                                *
!     * Begin execution.                                               *
!     *                                                                *
!     ******************************************************************
!
      !print *,'in verifydSdw...'
      if( myID==0 ) write(*,*) "Running verifydSdx..."

      ! Set the grid level of the current MG cycle, the value of the
      ! discretization and the logical correctForK.

      currentLevel = level
      discr        = spaceDiscr
      correctForK  = .false.
      fineGrid     = .true.

      ! Determine whether or not the total energy must be corrected
      ! for the presence of the turbulent kinetic energy and whether
      ! or not turbulence variables should be exchanged.

      correctForK  = .false.
      exchangeTurb = .false.
      secondhalo = .true.

      ! Allocate memory for the temporary arrays.

      ib = maxval(flowDoms(:,currentLevel,1)%ib)
      jb = maxval(flowDoms(:,currentLevel,1)%jb)
      kb = maxval(flowDoms(:,currentLevel,1)%kb)

      !determine the number of surface nodes for coupling matrix
      call mdCreateNSurfNodesLocal
      modFamID = max(0, 1_intType)
      nSurfNodesLocal = mdNSurfNodesLocal(modFamID)

      allocate(dSdwAD(3,nsurfnodeslocal,0:ib,0:jb,0:kb,nw), dSdwfd(3,nSurfNodesLocal,0:ib,0:jb,0:kb,nw))
  
       
      allocate(dSdwer(3,nSurfNodesLocal,0:ib,0:jb,0:kb,nw))
            
      allocate(forceLoc(3,nSurfNodesLocal), stat=ierr)
      if(ierr /= 0)                             &
           call terminate("verifyForceCoupling", &
           "Memory allocation failure for forceLoc")

      allocate(forceLocb(3,nSurfNodesLocal), stat=ierr)
      if(ierr /= 0)                             &
           call terminate("verifyForceCoupling", &
           "Memory allocation failure for forceLocb")

      allocate(forceLocp(3,nSurfNodesLocal), stat=ierr)
      if(ierr /= 0)                             &
           call terminate("verifyForceCoupling", &
           "Memory allocation failure for forceLocp")

      allocate(forceLocm(3,nSurfNodesLocal), stat=ierr)
      if(ierr /= 0)                             &
           call terminate("verifyForceCoupling", &
           "Memory allocation failure for forceLocm")
       
      forceLoc = zero
      forceLocp = zero
      forceLocm = zero

      ! Exchange the pressure if the pressure must be exchanged early.
      ! Only the first halo's are needed, thus whalo1 is called.
      ! Only on the fine grid.
      
      if(exchangePressureEarly .and. currentLevel <= groundLevel) &
           call whalo1(currentLevel, 1_intType, 0_intType, .true.,&
           .false., .false.)
      
      ! Apply all boundary conditions to all blocks on this level.
      
      call applyAllBC(secondHalo)
      
      ! Exchange the solution. Either whalo1 or whalo2
      ! must be called.
      
      if( secondHalo ) then
         call whalo2(currentLevel, 1_intType, nMGVar, .true., &
              .true., .true.)
      else
         call whalo1(currentLevel, 1_intType, nMGVar, .true., &
              .true., .true.)
      endif

      call mpi_barrier(SUmb_comm_world, ierr)      


      print *,"halo's updated"
!
!     ******************************************************************
!     *                                                                *
!     * Compute the d(forces)/dw (partial) using the tapenade routines.*
!     *                                                                *
!     ******************************************************************
         
!*********************
      ! Determine the reference point for the moment computation in
      ! meters.
      print *,'setting refpoint'
      refPoint(1) = LRef*pointRef(1)
      refPoint(2) = LRef*pointRef(2)
      refPoint(3) = LRef*pointRef(3)

       ! Initialize the force and moment coefficients to 0 as well as
       ! yplusMax.

       yplusMax = zero

   !    print *,'Adjoint forces initialized'
!
!***********************************
       print *,' computing adjoint derivatives'
       
   spectralLoopAdj: do sps=1,nTimeIntervalsSpectral
      ! Loop over the number of local blocks.
      print *,'starting domain loop'
      ii=0.0
      domainLoopAD: do nn=1,nDom

         ! Set some pointers to make the code more readable.
         print *,'setting pointers'
         call setPointersAdj(nn,level,sps)
         print *,'allocating memory'
         allocate(xAdj(0:ie,0:je,0:ke,3), stat=ierr)
         if(ierr /= 0)                              &
              call terminate("Memory allocation failure for xAdj.")
         
         allocate(xAdjB(0:ie,0:je,0:ke,3), stat=ierr)
         if(ierr /= 0)                              &
              call terminate("Memory allocation failure for xAdjB.")
         
         allocate(wAdj(0:ib,0:jb,0:kb,nw), stat=ierr)
         if(ierr /= 0)                              &
              call terminate("Memory allocation failure for wAdj.")
         
         allocate(wAdjB(0:ib,0:jb,0:kb,nw), stat=ierr)
         if(ierr /= 0)                              &
              call terminate("Memory allocation failure for wAdjB.")
        
         allocate(pAdj(0:ib,0:jb,0:kb), stat=ierr)
         if(ierr /= 0)                              &
              call terminate("Memory allocation failure for pAdj.")
         
         print *,'finished allocating',nn,level,sps
         righthanded = flowDoms(nn,level,sps)%righthanded
        

        
!!$        nViscBocos = flowDoms(nn,groundLevel,sps)%nViscBocos
!!$        nInvBocos  = flowDoms(nn,groundLevel,sps)%nInvBocos
!!$        
!!$        BCFaceID => flowDoms(nn,groundLevel,  1)%BCFaceID
!!$        groupNum => flowDoms(nn,groundLevel,  1)%groupNum
!!$
!!$        d2Wall   => flowDoms(nn,groundLevel,sps)%d2Wall
!!$        muLam    => flowDoms(nn,groundLevel,sps)%muLam
           
        ! Copy the coordinates into xAdj and
        ! Compute the face normals on the subfaces
          call copyADjointForcesStencil(wAdj,xAdj,alphaAdj,betaAdj,&
           MachAdj,machCoefAdj,prefAdj,rhorefAdj, pinfdimAdj, rhoinfdimAdj,&
           rhoinfAdj, pinfAdj,murefAdj, timerefAdj,pInfCorrAdj,nn,level,sps,&
           liftIndex)
  
        !call copyADjointForcesStencil(wAdj,xAdj,nn,level,sps)
        
        bocoLoop: do mm=1,nBocos

           ! Determine the range of cell indices of the owned cells
           ! Notice these are not the node indices
           iiBeg = BCData(mm)%icBeg
           iiEnd = BCData(mm)%icEnd
           jjBeg = BCData(mm)%jcBeg
           jjEnd = BCData(mm)%jcEnd
           
           i2Beg= BCData(mm)%inBeg+1; i2End = BCData(mm)%inEnd
           j2Beg= BCData(mm)%jnBeg+1; j2End = BCData(mm)%jnEnd
           
           ! Initialize the seed for reverse mode. Cl is the first one
           do m=1,nSurfNodesLocal
              do n=1,3
                 forcelocb(:,:) = zero
                 forcelocb(n,m) = 1
                 
                 xAdjB(:,:,:,:) = zero ! > return dS/dx
                 wAdjB(:,:,:,:) = zero ! > return dS/dW
                 !print *,'calling adjoint forces_b'
                 !===========================================================
                 !           
                 !print *,'Initial Parameters Calculated,Computing Lift Partials...'
                 !=========================================================
                 ! Compute the force derivatives
           call COMPUTEFORCECOUPLINGADJ_B(xadj, xadjb, wadj, wadjb, padj, &
&  iibeg, iiend, jjbeg, jjend, i2beg, i2end, j2beg, j2end, mm, yplusmax&
&  , refpoint, nsurfnodeslocal, forceloc, forcelocb, nn, level, sps, &
&  righthanded, secondhalo, alphaadj, alphaadjb, betaadj, betaadjb, &
&  machadj, machadjb, machcoefadj, prefadj, rhorefadj, pinfdimadj, &
&  rhoinfdimadj, rhoinfadj, pinfadj, murefadj, timerefadj, pinfcorradj, &
&  liftindex, ii)
          
           !print *,'wadjb',wadjb
           !print *,'xadjb',xadjb
           !stop
           do k = 0,kb
              do j = 0,jb
                 do i = 0,ib
                    do l = 1,nw
                       idxmgb = globalCell(i,j,k)
                    
                       !test = wadjb(i,j,k,l)
                       test = sum(wadjb(i,j,k,:))
                       dJdWlocal(:) = wAdjB(i,j,k,:)
                    
                       !print *,'secondaryindicies',i,j,k,ii,jj,kk
                       !if(i>zero .and. j>zero .and. k>zero .and. i<=ie .and. j<=je .and. k<=ke)then
                       !idxnode = globalNode(i,j,k)*3+l
                       idxSurf = (m-1)*3+n+ (mdNsurfNodes(myID,modFamID)*3)
                       idxres   = globalCell(i,j,k)*nw+l
                       if (wAdjb(i,j,k,l).ne.0.0)then
!!$                          if (m == 3) then
!!$                             print *,'wadjb',wadjb(i,j,k,l),i,j,k,l
!!$                          end if
                          call MatSetValues(dSdw, 1, idxSurf-1, 1, idxres-1,   &
                               wAdjb(i,j,k,l), INSERT_VALUES, PETScIerr)
                          if( PETScIerr/=0 ) &
                               print *,'matrix setting error'!call errAssemb("MatSetValues", "verifydrdw")
                          dSdwAD(n,m,i,j,k,l) = wAdjb(i,j,k,l)
!!$                          if (m==3) then
!!$                             print *,'dSdwAD',dSdwAD(n,m,i,j,k,l)
!!$                          end if
                       endif

                       !dSdwAD(n,m,i,j,k,l) = wAdjb(i,j,k,l)
                       !endif
                    enddo
                 enddo
              enddo
           enddo
           
        enddo
     enddo
     !print *,'ii1',ii
     ! Update the counter ii.
     
     ii = ii + (j2End-j2Beg+2)*(i2End-i2Beg+2)
     !print *,'ii',ii
  enddo bocoLoop
          !===============================================================
        
        !print *,' deallocating'
        ! Deallocate the xAdj.
        deallocate(pAdj, stat=ierr)
        if(ierr /= 0)                              &
             call terminate("verifydCfdx", &
             "Deallocation failure for xAdj.")
             
        ! Deallocate the xAdj.
        deallocate(wAdj, stat=ierr)
        if(ierr /= 0)                              &
             call terminate("verifydCfdx", &
             "Deallocation failure for xAdj.") 

         deallocate(wAdjB, stat=ierr)
        if(ierr /= 0)                              &
             call terminate("verifydCfdx", &
             "Deallocation failure for xAdj.") 
        ! Deallocate the xAdj.
        deallocate(xAdj, stat=ierr)
        if(ierr /= 0)                              &
             call terminate("verifydCfdx", &
             "Deallocation failure for xAdj.") 

         deallocate(xAdjB, stat=ierr)
        if(ierr /= 0)                              &
             call terminate("verifydCfdx", &
             "Deallocation failure for xAdj.") 
        !print *,'finishhed deallocating'
       
      enddo domainLoopAD

   enddo spectralLoopAdj

!
!     ******************************************************************
!     *                                                                *
!     * Complete the PETSc matrix assembly process.                    *
!     *                                                                *
!     ******************************************************************
!
      ! MatAssemblyBegin - Begins assembling the matrix. This routine
      !  should be called after completing all calls to MatSetValues().
      !
      ! Synopsis
      !
      ! #include "petscmat.h" 
      ! PetscErrorCode PETSCMAT_DLLEXPORT MatAssemblyBegin(Mat mat, &
      !                                            MatAssemblyType type)
      !
      ! Collective on Mat
      !
      ! Input Parameters
      !   mat  - the matrix
      !   type - type of assembly, either MAT_FLUSH_ASSEMBLY or
      !          MAT_FINAL_ASSEMBLY
      ! Notes
      ! MatSetValues() generally caches the values. The matrix is ready
      !  to use only after MatAssemblyBegin() and MatAssemblyEnd() have
      !  been called. Use MAT_FLUSH_ASSEMBLY when switching between
      !  ADD_VALUES and INSERT_VALUES in MatSetValues(); use
      !  MAT_FINAL_ASSEMBLY for the final assembly before using the
      !  matrix.
      !
      ! see .../petsc/docs/manualpages/Mat/MatAssemblyBegin.html

      call MatAssemblyBegin(dSdw,MAT_FINAL_ASSEMBLY,PETScIerr)

      if( PETScIerr/=0 ) &
        call terminate("verifydSdw", &
                       "Error in MatAssemblyBegin X")

      ! MatAssemblyEnd - Completes assembling the matrix. This routine
      !                  should be called after MatAssemblyBegin().
      !
      ! Synopsis
      !
      ! #include "petscmat.h" 
      ! PetscErrorCode PETSCMAT_DLLEXPORT MatAssemblyEnd(Mat mat,&
      !                                            MatAssemblyType type)
      !
      ! Collective on Mat
      !
      ! Input Parameters
      !   mat  - the matrix
      !   type - type of assembly, either MAT_FLUSH_ASSEMBLY or
      !          MAT_FINAL_ASSEMBLY
      !
      ! see .../petsc/docs/manualpages/Mat/MatAssemblyEnd.html

      call MatAssemblyEnd  (dSdw,MAT_FINAL_ASSEMBLY,PETScIerr)

      if( PETScIerr/=0 ) &
        call terminate("verifydSdw", &
                       "Error in MatAssemblyEnd S")

      ! Let PETSc know that the dRda matrix retains the same nonzero 
      ! pattern, in case the matrix is assembled again, as for a new
      ! point in the design space.

      ! MatSetOption - Sets a parameter option for a matrix.
      !   Some options may be specific to certain storage formats.
      !   Some options determine how values will be inserted (or added).
      !   Sorted,row-oriented input will generally assemble the fastest.
      !   The default is row-oriented, nonsorted input.
      !
      ! Synopsis
      !
      ! #include "petscmat.h" 
      ! call MatSetOption(Mat mat,MatOption op,PetscErrorCode ierr)
      !
      ! Collective on Mat
      !
      ! Input Parameters
      !   mat    - the matrix
      !   option - the option, one of those listed below (and possibly
      !     others), e.g., MAT_ROWS_SORTED, MAT_NEW_NONZERO_LOCATION_ERR
      !
      ! see .../petsc/docs/manualpages/Mat/MatSetOption.html
      ! or PETSc users manual, pp.52

      call MatSetOption(dSdw,MAT_NO_NEW_NONZERO_LOCATIONS,PETScIerr)

      if( PETScIerr/=0 ) &
        call terminate("verifydSdw", &
                       "Error in MatSetOption X")

      ! Get new time and compute the elapsed time.

!!$      call cpu_time(time(2))
!!$      timeAdjLocal = time(2)-time(1)
!!$
!!$      ! Determine the maximum time using MPI reduce
!!$      ! with operation mpi_max.
!!$
!!$      call mpi_reduce(timeAdjLocal, timeAdj, 1, sumb_real, &
!!$                      mpi_max, 0, PETSC_COMM_WORLD, PETScIerr)
!!$
!!$      if( PETScRank==0 ) &
!!$        write(*,20) "Assembling dS/dw matrix time (s) =", timeAdj
      
   print *,'AD loop finished'
   !stop
      ! Get new time and compute the elapsed AD time.

      call mpi_barrier(SUmb_comm_world, ierr)
      if(myID == 0) then
        call cpu_time(time(2))
        timeAdj = time(2)-time(1)
      endif
!
!     ******************************************************************
!     *                                                                *
!     * Compute d(Cf)/d(x) using central finite-differences.           *
!     *                                                                *
!     ******************************************************************
!
      ! Get the initial FD time.
      
      call mpi_barrier(SUmb_comm_world, ierr)
      if(myID == 0) call cpu_time(time(3))

!version using original routines!
      ! Loop over the number of local blocks.
      
      sps=1
      print *,'starting FD loop',sps
      domainForcesLoopFDorig: do nn=1,nDom   
         
         call setPointers(nn,level,sps)

         !loop over all points

         do i = 0,ib
            print *,'i=',i
            do j = 0,jb
               do k = 0,kb
                  !print *,'k',k
                  do l = 1,nw
                     wref = w(i,j,k,l)

                     w(i,j,k,l) = wref+deltaw

                     !*************************************************************
                     !Original force and metric calculation....
                     !     ******************************************************************
                     !     *                                                                *
                     !     * Update the force coefficients using the usual flow solver      *
                     !     * routine.                                                       *
                     !     *                                                                *
                     !     ******************************************************************
                     !
 
                     call metric(level)
                     call setPointers(nn,level,sps)
                     call computeForcesPressureAdj(w, p)
                     call applyAllBC(secondHalo)
                     call setPointers(nn,level,sps)
                     call mdCreateSurfForceListLocal(sps,famID,startInd,endInd)

 
                     forceLocp = mdSurfForcelocal
                     
                     
                     
                     !*********************
                     !Now calculate other perturbation
                     w(i,j,k,l) = wref-deltaw
                     
                     !*************************************************************
                     !Original force and metric calculation....
                     !     ******************************************************************
                     !     *                                                                *
                     !     * Update the force coefficients using the usual flow solver      *
                     !     * routine.                                                       *
                     !     *                                                                *
                     !     ******************************************************************
                     !
  
                     call metric(level)
                     call setPointers(nn,level,sps)
                     call computeForcesPressureAdj(w, p)
                     call applyAllBC(secondHalo)
                     call setPointers(nn,level,sps)
                     call mdCreateSurfForceListLocal(sps,famID,startInd,endInd)

 
                     forceLocm = mdSurfForcelocal


                     
                     w(i,j,k,l) = wref
                     
                     do n=1,3
                        do m=1,nSurfNodesLocal
                           dSdwFD(n,m,i,j,k,l) = (forcelocp(n,m)-forcelocm(n,m))/(two*deltaw)
                     
                        enddo
                     enddo
                  enddo
               enddo
            enddo
         enddo
      enddo domainForcesLoopFDorig
         print *,'finished fd'


  
      ! Get new time and compute the elapsed FD time.

      call mpi_barrier(SUmb_comm_world, ierr)
      if(myID == 0) then
        call cpu_time(time(4))
        timeFD = time(4)-time(3)
      endif
!
!     ******************************************************************
!     *                                                                *
!     * Output debug information.                                      *
!     *                                                                *
!     ******************************************************************
!
      ! Output debug information.
      print *,'Output debug information'
      domainDebugLoop: do nn=1,nDom

        ! Set the variables, which are related to the dimensions of the
        ! block. In this way the dimensions of the automatic arrays used
        ! in the flux routines are set a bit easier.
         print *,'setting pointers',nn,level,sps
         call setPointers(nn,level,sps)
         print *,'done pointers'
!!$
!!$        il = flowDoms(nn,currentLevel,1)%il
!!$        jl = flowDoms(nn,currentLevel,1)%jl
!!$        kl = flowDoms(nn,currentLevel,1)%kl

!!$        ! Loop over the location of the output cell.
!!$         if (myID == 0) then
!!$         print *,'shapes:',shape(dSdwfd),shape(dSdwAD),shape(dSdwer)
!!$         print *,'NsurfNodesLocal',nSurfNodesLocal
!!$         print *,'kb:',kb
!!$         print *,'jb:',jb
!!$         print *,'ib:',ib
!!$         print *,'nw:',nw
!!$      end if
         
         
         do n=1,3
            do m=1,nSurfNodesLocal
               do k=0,kb
                  do j=0,jb
                     do i=0,ib
                        
                        !write(*,10) "Jacobian dSdwer,dSdwAD,dSdwfd @ proc/block", &
                        !     myID, nn, "for cell", i,j,k, 'for node',m,n
                        !  error
                       
                        do l=1,nw
                         
                          
                           if ( dSdwfd(n,m,i,j,k,l) < 1e-10 ) then
                              dSdwer(n,m,i,j,k,l)  = zero
                           else
                              dSdwer(n,m,i,j,k,l)  =                   &
                                   (  dSdwAD(n,m,i,j,k,l)      &
                                   - dSdwfd(n,m,i,j,k,l) ) /dSdwfd(n,m,i,j,k,l)
                           endif
                 
                           ! Output if error
                        
                           if (dSdwer(n,m,i,j,k,l)/=0)          &
                           write(*,20) (dSdwer(n,m,i,j,k,l)), &
                                (dSdwAD(n,m,i,j,k,l)),   &
                                (dSdwfd(n,m,i,j,k,l)),i,j,k,l,m,n
                           !print *, 'nn,n,m,k,j,i,l',nn,n,m,k,j,i,l
                        enddo
                     enddo
                  enddo
               enddo
            enddo
         enddo
     
      enddo domainDebugLoop
  
  ! Flush the output buffer and synchronize the processors.
  
  call f77flush()
  call mpi_barrier(SUmb_comm_world, ierr)
  
  ! Output elapsed time for the adjoint and FD computations.
  
  if( myID==0 ) then
     print *, "====================================================="
     print *, " Time for reverse mode       =", timeAdj
     print *, " Time for finite differences =", timeFD
     print *, " Factor                      =", timeFD/timeAdj
     print *, "====================================================="
  endif

!
!     ******************************************************************
!     *                                                                *
!     * Compute the errors in dCf/dx.                                   *
!     *                                                                *
!     ******************************************************************
!
!      write(*,*)
!      write(*,30) "dSdwer : proc, min/loc, max/loc =", myID,          &
!                 minval(dSdwer(:,:,:,:,:,:)), minloc(dSdwer(:,:,:,:,:,:)), &
!                 maxval(dSdwer(:,:,:,:,:,:)), maxloc(dSdwer(:,:,:,:,:,:))
 

      ! Flush the output buffer and synchronize the processors.

      call f77flush()
      call mpi_barrier(SUmb_comm_world, ierr)
!
!     ******************************************************************
!

      
      ! Deallocate memory for the temporary arrays.
      !print *,'deallocating dcl'
      deallocate(dSdwAD,  dSdwfd,  dSdwer)
      deallocate(forceloc,forcelocb,forcelocp,forcelocm)


      !print *,'finished deallocating dcl'
  
      ! Output formats.

  10  format(1x,a,1x,i3,1x,i3,1x,a,1x,i3,1x,i3,1x,i3)           
  20  format(1x,(e18.6),2x,(e18.6),2x,(e18.6),1x,i3,1x,i3,1x,i3,1x,i3,1x,i3,1x,i3)
  30  format(1x,a,1x,i3,2x,e13.6,1x,5(i2,1x),3x,e13.6,1x,5(i2,1x))
  99  format(a,1x,i6)
    end subroutine verifydSdw
