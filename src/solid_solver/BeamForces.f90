subroutine get_surface_pressure_jump (time, beam, p, testing, timelevel)
  use mpi
  use fsi_vars
  use interpolation
  implicit none
  real(kind=pr),intent (in) :: time
  type(solid),intent (inout) :: beam
  character(len=*), intent(in), optional :: testing, timelevel
  real(kind=pr), intent (inout)   :: p(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  real(kind=pr) :: xf,yf,zf,soft_startup, t0
  real(kind=pr) :: psi,gamma,tmp,tmp2,psi_dt,beta_dt,gamma_dt,beta

  real(kind=pr),dimension(1:3) :: x, x_plate, x0_plate
  real(kind=pr),dimension(1:3) :: u_tmp,rot_body,v_tmp,v0_plate
  real(kind=pr),dimension(1:3,1:3) :: M_plate
  real(kind=pr),dimension(:,:),allocatable::ghostsy,ghostsz
  integer :: nh,is,ih,isurf,mpicode
  t0 = MPI_wtime()
  
  !-- get relative coordinate system
  call plate_coordinate_system( time,x0_plate,v0_plate,psi,beta,gamma,psi_dt,beta_dt,gamma_dt,M_plate)

  !-- get plate geometry
  call plate_geometry( beam, nh, M_plate, x0_plate )
!   call plate_geometry( beam, surfaces, active_points, nh, M_plate, x0_plate )
  
  ! surface pressure arrays:
  if(.not.allocated(p_surface)) allocate(p_surface(0:ns-1,0:nh,1:2))
  if(.not.allocated(p_surface_local)) allocate(p_surface_local(0:ns-1,0:nh,1:2))

  p_surface = 17.d0
  p_surface_local = 17.d0

    
  !-----------------------------------------------------------------------------
  ! Tri-linear interpolation of all points on the surface. 
  ! If the point does not lie in the locally stores memory, zero is set
  ! Then, we can sum over all MPI processes and have the complete pressure on
  ! the surface on all ranks (before T_release, we can skip this expensive part
  ! since we will return zero anyways)
  !-----------------------------------------------------------------------------
  if (time > T_release) call synchronize_ghosts ( p )
  
  do is=0,ns-1
    do ih=0,nh
      do isurf=1,2
        x = surfaces(is,ih,isurf,1:3)
        if (interp=='linear') then
          call trilinear_interp_ghosts( x, p, p_surface_local(is,ih,isurf))
        elseif (interp=='delta') then
          call delta_interpolation( x, p, p_surface_local(is,ih,isurf))
        endif
      enddo
    enddo
  enddo
  
  
  !-----------------------------------------------------------------------------
  ! All CPUs now interpolated some values of p on the surfaces, if they lie in
  ! their local memory (or on the lines between two CPUs). If not, they saved 
  ! -9.9e10. The max of all pressure distributions is now what we wanted to have
  ! p_surface is available on all CPU (and it has to since all evolve the solid)
  !-----------------------------------------------------------------------------
  call MPI_ALLREDUCE ( p_surface_local,p_surface,size(p_surface_local),&
                       MPI_DOUBLE_PRECISION,MPI_MAX,MPI_COMM_WORLD,mpicode) 

  !-----------------------------------------------------------------------------
  ! Testing. Interpolate the mask function (given by p from external) at the beam
  ! surfaces. the value should be in the range 0.05 and 0.60 (roughly). ideally,
  ! the value should be 0.5
  !-----------------------------------------------------------------------------
  if (present(testing)) then
  if (((testing=="mask").or.(testing=="linear")).and.(root)) then
    write(*,'(80("-"))')
    write(*,*) testing//" Interpolation test, top surface:"
    do ih=0,nh
      do is=0,ns-1      
        if (testing=="mask") then
          write(*,'((f5.3,1x))',advance='no') p_surface(is,ih,1)
        elseif (testing=="linear") then
          write(*,'((f5.3,1x))',advance='no') p_surface(is,ih,1)&
          -sin(surfaces(is,ih,1,2))*cos(surfaces(is,ih,1,3))
        endif
      enddo
      write(*,*) " "
    enddo
    write(*,*) testing//" Interpolation test, bottom surface:"
    do ih=0,nh
      do is=0,ns-1
        if (testing=="mask") then
          write(*,'((f5.3,1x))',advance='no') p_surface(is,ih,2)
        elseif (testing=="linear") then
          write(*,'((f5.3,1x))',advance='no') p_surface(is,ih,2)&
          -sin(surfaces(is,ih,2,2))*cos(surfaces(is,ih,2,3))
        endif
      enddo
      write(*,*) " "
    enddo
    write(*,'(80("-"))  ')
  endif
  endif
  
  !-----------------------------------------------------------------------------
  ! To avoid startup problems, we can smoothly "turn on" the coupling by 
  ! multiplying the pressure with a startup conditioner.
  ! Note this does not apply for gravity or imposed motion.
  !-----------------------------------------------------------------------------  
  soft_startup = startup_conditioner(time,T_release,tau)
  
  !-----------------------------------------------------------------------------
  ! Mask inactive points 
  !-----------------------------------------------------------------------------
  p_surface(:,:,1)=p_surface(:,:,1)*active_points
  p_surface(:,:,2)=p_surface(:,:,2)*active_points
  
  !-----------------------------------------------------------------------------
  ! Average the pressure in the spanwise direction and multiply with startup 
  ! conditioner. 
  !-----------------------------------------------------------------------------    
  if (.not.(present(testing))) then
    do is=0,ns-1 
      if (present(timelevel)) then
        if (timelevel=="old") then
          !-- store result of interpolation at OLD timelevel
          beam%pressure_old(is) = sum(p_surface(is,:,1)-p_surface(is,:,2))
          beam%pressure_old(is) = beam%pressure_old(is)*soft_startup
        elseif (timelevel=="new") then
          !-- store result of interpolation at NEW timelevel
          beam%pressure_new(is) = sum(p_surface(is,:,1)-p_surface(is,:,2))       
          beam%pressure_new(is) = beam%pressure_new(is)*soft_startup
        endif
      else
        ! write into both
        beam%pressure_old(is) = sum(p_surface(is,:,1)-p_surface(is,:,2)) 
        beam%pressure_new(is) = sum(p_surface(is,:,1)-p_surface(is,:,2))
        
        beam%pressure_old(is) = beam%pressure_old(is)*soft_startup
        beam%pressure_new(is) = beam%pressure_new(is)*soft_startup
      endif      
      
      ! average:
      beam%pressure_old(is) = beam%pressure_old(is) / sum(active_points(is,:))
      beam%pressure_new(is) = beam%pressure_new(is) / sum(active_points(is,:))
    enddo
  endif
  
  if (time <= T_release) then
    beam%pressure_new = 0.d0
    beam%pressure_old = 0.d0
  endif
      
!   deallocate(surfaces)
!   deallocate(p_surface)
!   deallocate(p_surface_local)
  
  time_surf = time_surf + MPI_wtime() - t0
end subroutine get_surface_pressure_jump


!-------------------------------------------------------------------------------
! Testing routine for the surface interpolation, called in every run. First, we
! interpolate the mask function at the beams's surface - the value must be close 
! to 0.5. If not, then mask function and solid model are not consistently defned.
! Second, we interpolate and analytic function f=(y*z) to compare with the exact
! value. the error should be zero
!
! subroutine GET_SURFACE_PRESSURE_JUMP has an optional argument for this testing
!
!-------------------------------------------------------------------------------
subroutine surface_interpolation_testing( time, beams, work )
  use mpi
  use fsi_vars
  use interpolation
  use penalization
  use insect_module
  implicit none
  real(kind=pr),intent (in) :: time
  type(solid),dimension(1:nbeams),intent (inout) :: beams
  real(kind=pr),intent(inout):: work(ga(1):gb(1),ga(2):gb(2),ga(3):gb(3))
  integer :: ix,iy,iz
  real(kind=pr) :: x,y,z
  type(diptera)::insectdummy
  
  !-- create mask
!   call Draw_flexible_plate(time, beam)
  call create_mask(time,insectdummy,beams)
  !-- copy mask in extended array (the one with ghost points)
  work(ra(1):rb(1),ra(2):rb(2),ra(3):rb(3)) = mask*eps
  !-- interpolate the mask at the beam surfaces
  call get_surface_pressure_jump (time, beams(1), work, testing="mask")

  work=0.d0
  !-- the array "mask" with some values (analytic)
  do iz=ra(3),rb(3)
    do iy=ra(2),rb(2)
      do ix=ra(1),rb(1)
        x=dble(ix)*dx
        y=dble(iy)*dy
        z=dble(iz)*dz
        work(ix,iy,iz)=sin(y)*cos(z)
      enddo
    enddo
  enddo 
  !-- interpolate these values on the surface and compare to exact solution
  call get_surface_pressure_jump (time, beams(1), work, testing="linear")
  
  
end subroutine
