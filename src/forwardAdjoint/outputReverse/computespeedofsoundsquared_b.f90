   !        Generated by TAPENADE     (INRIA, Tropics team)
   !  Tapenade 3.10 (r5363) -  9 Sep 2014 09:53
   !
   !  Differentiation of computespeedofsoundsquared in reverse (adjoint) mode (with options i4 dr8 r8 noISIZE):
   !   gradient     of useful results: *aa *p *gamma *w
   !   with respect to varying inputs: *p *gamma *w
   !   Plus diff mem management of: aa:in p:in gamma:in w:in
   !
   !      ******************************************************************
   !      *                                                                *
   !      * File:          computeSpeedOfSoundSquared.F90                  *
   !      * Author:        Gaetan K.W. Kenway                              *
   !      * Starting date: 01-20-2014                                      *
   !      * Last modified: 01-20-2014                                      *
   !      *                                                                *
   !      ******************************************************************
   !
   SUBROUTINE COMPUTESPEEDOFSOUNDSQUARED_B(correctfork)
   !
   !      ******************************************************************
   !      *                                                                *
   !      * computeSpeedOfSoundSquared does what it says.                  *
   !      *                                                                *
   !      ******************************************************************
   !
   USE BLOCKPOINTERS
   USE CONSTANTS
   IMPLICIT NONE
   !
   !      Input Parameters
   !
   LOGICAL, INTENT(IN) :: correctfork
   !
   !      Local variables.
   !
   REAL(kind=realtype), PARAMETER :: twothird=two*third
   INTEGER(kind=inttype) :: i, j, k, ii
   REAL(kind=realtype) :: pp
   REAL(kind=realtype) :: ppd
   INTRINSIC MOD
   REAL(kind=realtype) :: temp0
   REAL(kind=realtype) :: tempd
   REAL(kind=realtype) :: tempd0
   REAL(kind=realtype) :: temp
   IF (correctfork) THEN
   DO ii=0,ie*je*ke-1
   i = MOD(ii, ie) + 1
   j = MOD(ii/ie, je) + 1
   k = ii/(ie*je) + 1
   pp = p(i, j, k) - twothird*w(i, j, k, irho)*w(i, j, k, itu1)
   temp = w(i, j, k, irho)
   tempd = aad(i, j, k)/temp
   gammad(i, j, k) = gammad(i, j, k) + pp*tempd
   ppd = gamma(i, j, k)*tempd
   wd(i, j, k, irho) = wd(i, j, k, irho) - gamma(i, j, k)*pp*tempd/&
   &       temp
   aad(i, j, k) = 0.0_8
   pd(i, j, k) = pd(i, j, k) + ppd
   wd(i, j, k, irho) = wd(i, j, k, irho) - twothird*w(i, j, k, itu1)*&
   &       ppd
   wd(i, j, k, itu1) = wd(i, j, k, itu1) - twothird*w(i, j, k, irho)*&
   &       ppd
   END DO
   ELSE
   DO ii=0,ie*je*ke-1
   i = MOD(ii, ie) + 1
   j = MOD(ii/ie, je) + 1
   k = ii/(ie*je) + 1
   temp0 = w(i, j, k, irho)
   tempd0 = aad(i, j, k)/temp0
   gammad(i, j, k) = gammad(i, j, k) + p(i, j, k)*tempd0
   pd(i, j, k) = pd(i, j, k) + gamma(i, j, k)*tempd0
   wd(i, j, k, irho) = wd(i, j, k, irho) - gamma(i, j, k)*p(i, j, k)*&
   &       tempd0/temp0
   aad(i, j, k) = 0.0_8
   END DO
   END IF
   END SUBROUTINE COMPUTESPEEDOFSOUNDSQUARED_B
