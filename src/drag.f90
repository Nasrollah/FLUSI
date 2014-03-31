!-------------------------------------------------------------------------------
! Compute hydrodynamic forces and torque
!-------------------------------------------------------------------------------
! The forces are the volume integral of the penalization term. Different parts of
! the mask are colored differently.
! Color         Description
!   0           Boring parts (channel walls, cavity)
!   1           Interesting parts (e.g. a cylinder), for the insects this is WINGS
!   2           Other parts, for the insects, this is BODY
! Currently, we store the torque / forces over all colors greater than 0 in the
! global structure "GlobalIntegrals". If we're running in "insects" mode, the 
! colors 1 and 2 are the forces on wings and body, respectively. These are stored
! in the "Insect" global struct.
!-------------------------------------------------------------------------------
subroutine cal_drag ( time, u )
  use mpi
  use fsi_vars
  implicit none
  
  real(kind=pr),intent(in) :: u(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3),1:nd)
  real(kind=pr),intent(in) :: time
  
  integer :: ix,iy,iz, mpicode,partid
  integer(kind=2) :: color
  real(kind=pr) :: penalx,penaly,penalz,xlev,ylev,zlev
  ! we can choose up to 6 different colors
  real(kind=pr),dimension(0:5) :: torquex,torquey,torquez,forcex,forcey,forcez
  character(len=1024) :: forcepartfilename
  
  forcex  = 0.d0
  forcey  = 0.d0
  forcez  = 0.d0  
  torquex = 0.d0
  torquey = 0.d0
  torquez = 0.d0
  
  !---------------------------------------------------------------------------
  ! loop over penalization term (this saves a work array)
  !---------------------------------------------------------------------------
  do ix=ra(1),rb(1)
    do iy=ra(2),rb(2)
      do iz=ra(3),rb(3)
        ! actual penalization term
        penalx = -mask(ix,iy,iz)*(u(ix,iy,iz,1)-us(ix,iy,iz,1))
        penaly = -mask(ix,iy,iz)*(u(ix,iy,iz,2)-us(ix,iy,iz,2))
        penalz = -mask(ix,iy,iz)*(u(ix,iy,iz,3)-us(ix,iy,iz,3))
        
        ! for torque moment
        xlev = dble(ix)*dx - x0
        ylev = dble(iy)*dy - y0
        zlev = dble(iz)*dz - z0
        
        ! what color does the point have?
        color = mask_color(ix,iy,iz)
        
        ! integrate forces + torques (note sign inversion!)
        forcex(color) = forcex(color) - penalx
        forcey(color) = forcey(color) - penaly
        forcez(color) = forcez(color) - penalz
        torquex(color) = torquex(color) - (ylev*penalz - zlev*penaly)
        torquey(color) = torquey(color) - (zlev*penalx - xlev*penalz)
        torquez(color) = torquez(color) - (xlev*penaly - ylev*penalx)
      enddo
    enddo
  enddo  
  
  !---------------------------------------------------------------------------
  ! save global forces
  !---------------------------------------------------------------------------
  forcex = forcex*dx*dy*dz
  forcey = forcey*dx*dy*dz
  forcez = forcez*dx*dy*dz  
  
  ! in the global structure, we store all contributions with color > 0, so we
  ! only EXCLUDE channel / cavity walls (the boring stuff)
  call MPI_ALLREDUCE ( sum(forcex(1:5)),GlobalIntegrals%Force(1),1,&
                  MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
  call MPI_ALLREDUCE ( sum(forcey(1:5)),GlobalIntegrals%Force(2),1,&
                  MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
  call MPI_ALLREDUCE ( sum(forcez(1:5)),GlobalIntegrals%Force(3),1,&
                  MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode) 
                  
  ! the insects have forces on the wing and body separate
  if (iMask=="Insect") then
    ! WINGS:
    call MPI_ALLREDUCE (forcex(1),Insect%PartIntegrals(1)%Force(1),1,&
                    MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
    call MPI_ALLREDUCE (forcey(1),Insect%PartIntegrals(1)%Force(2),1,&
                    MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode) 
    call MPI_ALLREDUCE (forcez(1),Insect%PartIntegrals(1)%Force(3),1,&
                    MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)
    ! BODY:
    call MPI_ALLREDUCE (forcex(2),Insect%PartIntegrals(2)%Force(1),1,&
                    MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
    call MPI_ALLREDUCE (forcey(2),Insect%PartIntegrals(2)%Force(2),1,&
                    MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode) 
    call MPI_ALLREDUCE (forcez(2),Insect%PartIntegrals(2)%Force(3),1,&
                    MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)                    
  endif
  
  ! in the global structure, we store all contributions with color > 0, so we
  ! only EXCLUDE channel / cavity walls (the boring stuff)                  
  torquex = torquex*dx*dy*dz
  torquey = torquey*dx*dy*dz
  torquez = torquez*dx*dy*dz  
  
  call MPI_ALLREDUCE ( sum(torquex(1:5)),GlobalIntegrals%Torque(1),1,&
          MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
  call MPI_ALLREDUCE ( sum(torquey(1:5)),GlobalIntegrals%Torque(2),1,&
          MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode) 
  call MPI_ALLREDUCE ( sum(torquez(1:5)),GlobalIntegrals%Torque(3),1,&
          MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
          
  ! the insects have forces on the wing and body separate
  if (iMask=="Insect") then
    ! WINGS:
    call MPI_ALLREDUCE (torquex(1),Insect%PartIntegrals(1)%Torque(1),1,&
            MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
    call MPI_ALLREDUCE (torquey(1),Insect%PartIntegrals(1)%Torque(2),1,&
            MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode) 
    call MPI_ALLREDUCE (torquez(1),Insect%PartIntegrals(1)%Torque(3),1,&
            MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)
    ! BODY:
    call MPI_ALLREDUCE (torquex(2),Insect%PartIntegrals(2)%Torque(1),1,&
            MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
    call MPI_ALLREDUCE (torquey(2),Insect%PartIntegrals(2)%Torque(2),1,&
            MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode) 
    call MPI_ALLREDUCE (torquez(2),Insect%PartIntegrals(2)%Torque(3),1,&
            MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)                    
  endif
  
  
  !---------------------------------------------------------------------------
  ! write time series to disk
  ! note: we also dump the unst corrections and thus suppose that they
  ! have been computed ( call cal_unst_corrections first! )
  !---------------------------------------------------------------------------
  if(mpirank == 0) then
    open(14,file='forces.t',status='unknown',position='append')
    write (14,'(13(e12.5,1x))') time, GlobalIntegrals%Force, &
    GlobalIntegrals%Force_unst, GlobalIntegrals%Torque, &
    GlobalIntegrals%Torque_unst
    close(14)
    
    ! currently, only insects have different colors
    if (iMask=="Insect") then
    do partid=1,2
    write (forcepartfilename, "(A11,I1,A2)") "forces_part", partid, ".t"
    open(14,file=trim(forcepartfilename),status='unknown',position='append')
    write (14,'(13(e12.5,1x))') time, Insect%PartIntegrals(partid)%Force, &
    Insect%PartIntegrals(partid)%Force_unst, Insect%PartIntegrals(partid)%Torque, &
    Insect%PartIntegrals(partid)%Torque_unst
    close(14)
    enddo
    endif
    
  endif
end subroutine cal_drag



!-------------------------------------------------------------------------------
! computes the unsteady corrections, if this is set in the params file
! INPUT: 
!       time, dt: current time level and OLD time step
!       NOTE: the mask is at time t(n), so dt=t(n)-t(n-1)
! OUTPUT:
!       saves the unsteady corrections in the global force datatype
! NOTES:
!       this code uses persistent variables to determine the time derivative.
!       it will fail in the very first time step, also after retaking a backup. 
!       if it is not possible to compute the unst corrections, we return 0 here.
!-------------------------------------------------------------------------------
subroutine cal_unst_corrections ( time, dt )
  use mpi
  use fsi_vars
  implicit none
  real(kind=pr),intent(in) :: time, dt
  ! is it possible to compute unsteady forces?
  logical, save :: is_possible = .false.
  ! the old value of the integral, component by component, for each color
  real(kind=pr),dimension(0:5),save :: force_oldx = 0.d0
  real(kind=pr),dimension(0:5),save :: force_oldy = 0.d0
  real(kind=pr),dimension(0:5),save :: force_oldz = 0.d0
  real(kind=pr),dimension(0:5),save :: torque_oldx = 0.d0
  real(kind=pr),dimension(0:5),save :: torque_oldy = 0.d0
  real(kind=pr),dimension(0:5),save :: torque_oldz = 0.d0
  real(kind=pr) :: xlev,ylev,zlev,norm,usx,usy,usz
  ! we have up to 6 different colors
  real(kind=pr),dimension(0:5) :: force_new_locx, force_new_locy, force_new_locz
  real(kind=pr),dimension(0:5) :: torque_new_locx, torque_new_locy, torque_new_locz
  real(kind=pr),dimension(0:5) :: force_newx, force_newy, force_newz
  real(kind=pr),dimension(0:5) :: torque_newx, torque_newy, torque_newz
  
  integer :: mpicode, ix, iy, iz
  integer(kind=2) :: color
  
  !-----------------------------------------------------------------------------
  ! force
  !-----------------------------------------------------------------------------
  force_new_locx = 0.0
  force_new_locy = 0.0
  force_new_locz = 0.0
  
  norm = dx*dy*dz*eps
  
  do ix=ra(1),rb(1)
    do iy=ra(2),rb(2)
      do iz=ra(3),rb(3)
        color = mask_color(ix,iy,iz)
        ! sum up new integral as a function of color
        force_new_locx(color) = force_new_locx(color)+mask(ix,iy,iz)*us(ix,iy,iz,1)*norm
        force_new_locy(color) = force_new_locy(color)+mask(ix,iy,iz)*us(ix,iy,iz,2)*norm
        force_new_locz(color) = force_new_locz(color)+mask(ix,iy,iz)*us(ix,iy,iz,3)*norm
      enddo
    enddo
  enddo  
    
  call MPI_ALLREDUCE(force_new_locx,force_newx,6,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
  call MPI_ALLREDUCE(force_new_locy,force_newy,6,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)   
  call MPI_ALLREDUCE(force_new_locz,force_newz,6,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)   
  
  if (is_possible) then
    ! here, we store the unsteady corrections for all nonzero colors in the global struct
    GlobalIntegrals%Force_unst(1) = sum(force_newx(1:5))-sum(force_oldx(1:5))
    GlobalIntegrals%Force_unst(2) = sum(force_newy(1:5))-sum(force_oldy(1:5))
    GlobalIntegrals%Force_unst(3) = sum(force_newz(1:5))-sum(force_oldz(1:5))    
    GlobalIntegrals%Force_unst = GlobalIntegrals%Force_unst / dt
    
    if (iMask=="Insect") then
      ! for the insects, we save separately the WING...
      Insect%PartIntegrals(1)%Force_unst(1) = force_newx(1)-force_oldx(1)
      Insect%PartIntegrals(1)%Force_unst(2) = force_newy(1)-force_oldy(1)
      Insect%PartIntegrals(1)%Force_unst(3) = force_newz(1)-force_oldz(1)
      Insect%PartIntegrals(1)%Force_unst = Insect%PartIntegrals(1)%Force_unst / dt
      ! ... and the BODY
      Insect%PartIntegrals(2)%Force_unst(1) = force_newx(2)-force_oldx(2)
      Insect%PartIntegrals(2)%Force_unst(2) = force_newy(2)-force_oldy(2)
      Insect%PartIntegrals(2)%Force_unst(3) = force_newz(2)-force_oldz(2)
      Insect%PartIntegrals(2)%Force_unst = Insect%PartIntegrals(2)%Force_unst / dt
    endif
  else
    ! we cannot compute the time derivative, because we lack the old value of the
    ! integral. As a hack, return zero.
    GlobalIntegrals%Force_unst = 0.d0    
    if (iMask=="Insect") then
      Insect%PartIntegrals(1)%Force_unst = 0.d0
      Insect%PartIntegrals(2)%Force_unst = 0.d0
    endif
  endif  
  
  ! iterate
  force_oldx = force_newx
  force_oldy = force_newy
  force_oldz = force_newz
    
  !-----------------------------------------------------------------------------
  ! torque
  !-----------------------------------------------------------------------------
  torque_new_locx = 0.d0
  torque_new_locy = 0.d0
  torque_new_locz = 0.d0
  
  do ix=ra(1),rb(1)
    do iy=ra(2),rb(2)
      do iz=ra(3),rb(3)  
        ! for torque moment
        xlev = dble(ix)*dx - x0
        ylev = dble(iy)*dy - y0
        zlev = dble(iz)*dz - z0    
        
        usx = us(ix,iy,iz,1)*mask(ix,iy,iz)*eps
        usy = us(ix,iy,iz,2)*mask(ix,iy,iz)*eps
        usz = us(ix,iy,iz,3)*mask(ix,iy,iz)*eps
        
        color = mask_color(ix,iy,iz)
        
        torque_new_locx(color) = torque_new_locx(color) + (ylev*usz - zlev*usy)
        torque_new_locy(color) = torque_new_locy(color) + (zlev*usx - xlev*usz)
        torque_new_locz(color) = torque_new_locz(color) + (xlev*usy - ylev*usx)   
      enddo
    enddo
  enddo
  
  torque_new_locx = torque_new_locx*dx*dy*dz
  torque_new_locy = torque_new_locy*dx*dy*dz
  torque_new_locz = torque_new_locz*dx*dy*dz
  
  call MPI_ALLREDUCE(torque_new_locx,torque_newx,6,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)  
  call MPI_ALLREDUCE(torque_new_locy,torque_newy,6,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)   
  call MPI_ALLREDUCE(torque_new_locz,torque_newz,6,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,mpicode)     
  
  
  if (is_possible) then
    ! here, we store the unsteady corrections for all nonzero colors in the global struct
    GlobalIntegrals%Torque_unst(1) = sum(torque_newx(1:5))-sum(torque_oldx(1:5))
    GlobalIntegrals%Torque_unst(2) = sum(torque_newy(1:5))-sum(torque_oldy(1:5))
    GlobalIntegrals%Torque_unst(3) = sum(torque_newz(1:5))-sum(torque_oldz(1:5))
    GlobalIntegrals%Torque_unst = GlobalIntegrals%Torque_unst / dt
    if (iMask=="Insect") then
      ! for the insects, we save separately the WING...
      Insect%PartIntegrals(1)%Torque_unst(1) = torque_newx(1)-torque_oldx(1)
      Insect%PartIntegrals(1)%Torque_unst(2) = torque_newy(1)-torque_oldy(1)
      Insect%PartIntegrals(1)%Torque_unst(3) = torque_newz(1)-torque_oldz(1)
      Insect%PartIntegrals(1)%Torque_unst = Insect%PartIntegrals(1)%Torque_unst / dt
      ! ... and the BODY
      Insect%PartIntegrals(2)%Torque_unst(1) = torque_newx(2)-torque_oldx(2)
      Insect%PartIntegrals(2)%Torque_unst(2) = torque_newy(2)-torque_oldy(2)
      Insect%PartIntegrals(2)%Torque_unst(3) = torque_newz(2)-torque_oldz(2)
      Insect%PartIntegrals(2)%Torque_unst = Insect%PartIntegrals(2)%Torque_unst / dt
    endif    
  else
    ! we cannot compute the time derivative, because we lack the old value of the
    ! integral. As a hack, return zero.
    GlobalIntegrals%Torque_unst = 0.d0   
    if (iMask=="Insect") then
      Insect%PartIntegrals(1)%Torque_unst = 0.d0
      Insect%PartIntegrals(2)%Torque_unst = 0.d0
    endif
  endif  
  
  ! iterate
  torque_oldx = torque_newx
  torque_oldy = torque_newy
  torque_oldz = torque_newz  
  
  ! now we sure have the old value in the next step
  is_possible = .true.
end subroutine cal_unst_corrections
