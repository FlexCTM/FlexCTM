module test_mesh
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   use mod_const, only: fp
   use mod_mesh, only: mesh_type
   use projection, only: proj_type, create_proj, PROJ_LCC
   use testdrive, only: check, error_type, new_unittest, unittest_type
   implicit none
   private
   public :: collect_tests
contains
   subroutine collect_tests(tests)
      type(unittest_type), allocatable, intent(out) :: tests(:)
      tests = [new_unittest('minimal latitude-longitude grid', test_minimal_latlon), &
               new_unittest('regular latitude-longitude grid', test_regular_latlon), &
               new_unittest('minimal Lambert grid', test_minimal_lambert), &
               new_unittest('regular Lambert grid', test_regular_lambert)]
   end subroutine collect_tests

   subroutine test_minimal_latlon(error)
      type(error_type), allocatable, intent(out) :: error
      type(mesh_type) :: mesh
      type(proj_type) :: projection_definition
      call mesh%init(110._fp, 20._fp, 1._fp, 1, 1, 0, projection_definition)
      call check_mesh(error, mesh, 1, 1)
      if (allocated(error)) return
      call check(error, abs(mesh%mlon(1, 1) - 110.5_fp) <= epsilon(1._fp), 'minimal-grid center longitude is incorrect')
      if (allocated(error)) return
      call check(error, abs(mesh%mlat(1, 1) - 20.5_fp) <= epsilon(1._fp), 'minimal-grid center latitude is incorrect')
   end subroutine test_minimal_latlon

   subroutine test_regular_latlon(error)
      type(error_type), allocatable, intent(out) :: error
      type(mesh_type) :: mesh
      type(proj_type) :: projection_definition
      call mesh%init(100._fp, 10._fp, 0.25_fp, 8, 6, 0, projection_definition)
      call check_mesh(error, mesh, 8, 6)
   end subroutine test_regular_latlon

   subroutine test_minimal_lambert(error)
      type(error_type), allocatable, intent(out) :: error
      type(mesh_type) :: mesh
      type(proj_type) :: projection_definition
      projection_definition = create_proj(PROJ_LCC, lon1=115._fp, lat1=30._fp, truelat1=20._fp, truelat2=40._fp)
      call mesh%init(-5000._fp, -5000._fp, 10000._fp, 1, 1, PROJ_LCC, projection_definition)
      call check_mesh(error, mesh, 1, 1)
   end subroutine test_minimal_lambert

   subroutine test_regular_lambert(error)
      type(error_type), allocatable, intent(out) :: error
      type(mesh_type) :: mesh
      type(proj_type) :: projection_definition
      projection_definition = create_proj(PROJ_LCC, lon1=115._fp, lat1=30._fp, truelat1=20._fp, truelat2=40._fp)
      call mesh%init(-40000._fp, -30000._fp, 10000._fp, 8, 6, PROJ_LCC, projection_definition)
      call check_mesh(error, mesh, 8, 6)
   end subroutine test_regular_lambert

   subroutine check_mesh(error, mesh, nx, ny)
      type(error_type), allocatable, intent(out) :: error
      type(mesh_type), intent(in) :: mesh
      integer, intent(in) :: nx, ny
      call check(error, all(shape(mesh%mlon) == [nx, ny]), 'mlon has the wrong shape')
      if (allocated(error)) return
      call check(error, all(shape(mesh%clon) == [nx + 1, ny + 1]), 'clon has the wrong shape')
      if (allocated(error)) return
      call check(error, all(ieee_is_finite(mesh%mlon)) .and. all(ieee_is_finite(mesh%mlat)), 'mass-grid coordinates must be finite')
      if (allocated(error)) return
      call check(error, all(ieee_is_finite(mesh%area)) .and. all(mesh%area > 0._fp), 'grid-cell areas must be finite and positive')
      if (allocated(error)) return
      call check(error, all(ieee_is_finite(mesh%xlen)) .and. all(ieee_is_finite(mesh%ylen)), 'grid-cell lengths must be finite')
   end subroutine check_mesh
end module test_mesh

program tester
   use, intrinsic :: iso_fortran_env, only: error_unit
   use testdrive, only: run_testsuite
   use test_mesh, only: collect_tests
   implicit none
   integer :: stat
   stat = 0
   call run_testsuite(collect_tests, error_unit, stat)
   if (stat > 0) error stop 'mesh tests failed'
end program tester
