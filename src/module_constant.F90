module mod_const
  !! 常数项
   ! use, intrinsic :: ieee_arithmetic
   use, intrinsic :: iso_fortran_env, only: real32, real64
   implicit none
   private

   public :: fp, pi, pi2, pi05, deg, rad, eps, inf
   public :: g, P00, Rd, RvRd, R_cp, vk, radius

#ifdef FLEXCTM_REAL32
   integer, parameter :: fp = real32
#else
   integer, parameter :: fp = real64
#endif

   real(fp), parameter :: pi = atan(1.0_fp)*4.0_fp
   real(fp), parameter :: pi2 = pi*2.0_fp
   real(fp), parameter :: pi05 = pi*0.5_fp
   real(fp), parameter :: deg = 180.0_fp/pi
   real(fp), parameter :: rad = pi/180.0_fp

   real(fp), parameter :: eps = epsilon(1.0_fp)
   real(fp), parameter :: inf = huge(1.0_fp)

   real(fp), parameter :: g = 9.81_fp    !! 重力加速度 m/s2
   real(fp), parameter :: P00 = 100000._fp !! 参照气压值 Pa

   real(fp), parameter :: Rd = 287.05_fp !!  气体常数 J/(kg·K)
   real(fp), parameter :: RvRd = 0.61_fp      !!  水汽气体常数/干空气气体常数
   real(fp), parameter :: R_cp = 0.286_fp  !!  R/cp, 气体常数/比热容

   real(fp), parameter :: vk = 0.41_fp !! Von Kármán constant

   real(fp), parameter :: radius = 6.371e6_fp  !! 地球半径

end module mod_const
