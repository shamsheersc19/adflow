!        Generated by TAPENADE     (INRIA, Tropics team)
!  Tapenade 3.3 (r3163) - 09/25/2009 09:03
!
!  Differentiation of getsurfacenormalscouplingadj in reverse (adjoint) mode:
!   gradient, with respect to input variables: pts
!   of linear combination of output variables: normadj
SUBROUTINE GETSURFACENORMALSCOUPLINGADJ_B(pts, ptsb, normadj, normadjb, &
&  righthanded)
  USE CONSTANTS
  IMPLICIT NONE
! Subroutine Arguments
  REAL(kind=realtype), INTENT(IN) :: pts(3, 3, 3)
  REAL(kind=realtype) :: ptsb(3, 3, 3)
  LOGICAL, INTENT(IN) :: righthanded
  REAL(kind=realtype) :: normadj(3, 2, 2)
  REAL(kind=realtype) :: normadjb(3, 2, 2)
! Local Variables
  INTEGER(kind=inttype) :: i, j
  REAL(kind=realtype) :: v1(3), v2(3), fact2
  REAL(kind=realtype) :: v1b(3), v2b(3)
  REAL(kind=realtype) :: tempb1
  REAL(kind=realtype) :: tempb0
  REAL(kind=realtype) :: tempb
  IF (righthanded) THEN
    fact2 = half
  ELSE
    fact2 = -half
  END IF
  DO j=1,2
    DO i=1,2
      CALL PUSHREAL8ARRAY(v1, realtype*3/8)
      v1(:) = pts(:, i+1, j+1) - pts(:, i, j)
      CALL PUSHREAL8ARRAY(v2, realtype*3/8)
      v2(:) = pts(:, i, j+1) - pts(:, i+1, j)
! The face normal, which is the cross product of the two
! diagonal vectors times fact; remember that fact2 is
! either -0.5 or 0.5.
    END DO
  END DO
  ptsb = 0.0
  DO j=2,1,-1
    DO i=2,1,-1
      v1b = 0.0
      v2b = 0.0
      tempb = fact2*normadjb(3, i, j)
      v1b(1) = v2(2)*tempb
      v2b(2) = v1(1)*tempb
      v1b(2) = -(v2(1)*tempb)
      normadjb(3, i, j) = 0.0
      tempb0 = fact2*normadjb(2, i, j)
      v2b(1) = v1(3)*tempb0 - v1(2)*tempb
      v1b(3) = v1b(3) + v2(1)*tempb0
      v1b(1) = v1b(1) - v2(3)*tempb0
      normadjb(2, i, j) = 0.0
      tempb1 = fact2*normadjb(1, i, j)
      v2b(3) = v2b(3) + v1(2)*tempb1 - v1(1)*tempb0
      v1b(2) = v1b(2) + v2(3)*tempb1
      v1b(3) = v1b(3) - v2(2)*tempb1
      v2b(2) = v2b(2) - v1(3)*tempb1
      normadjb(1, i, j) = 0.0
      CALL POPREAL8ARRAY(v2, realtype*3/8)
      ptsb(:, i, j+1) = ptsb(:, i, j+1) + v2b(:)
      ptsb(:, i+1, j) = ptsb(:, i+1, j) - v2b(:)
      CALL POPREAL8ARRAY(v1, realtype*3/8)
      ptsb(:, i+1, j+1) = ptsb(:, i+1, j+1) + v1b(:)
      ptsb(:, i, j) = ptsb(:, i, j) - v1b(:)
    END DO
  END DO
END SUBROUTINE GETSURFACENORMALSCOUPLINGADJ_B
