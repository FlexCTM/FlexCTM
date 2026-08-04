module mod_mete_diagnostic
   !! 基于 FlexCTM 标准气象数据统一计算数值过程所需的诊断量。
   use mod_const, only: fp
   use mod_block, only: block_type

   use parallel, only: tile_type
   use ysu, only: cal_pbl_param, cal_Kz_by_YSU
   use diffusion, only: cal_kh_by_deformation_method

   implicit none
   private

   public :: diagnose_meteorology

contains

   subroutine diagnose_meteorology(tile, iblock, dt)
      type(tile_type), intent(in) :: tile       !! 当前进程的数据切片。
      type(block_type), intent(inout) :: iblock !! 待更新的气象状态。
      real(fp), intent(in) :: dt                !! 当前积分时间步长。

      real(fp) :: u_mass(iblock%nz) !! 质量网格上的东向风。
      real(fp) :: v_mass(iblock%nz) !! 质量网格上的北向风。
      integer :: i, j, k

      do k = 1, iblock%nz
         iblock%volume(:, :, k) = iblock%mesh%area*iblock%dz(:, :, k)
         if (iblock%mesh%proj_id > 0) then
            call cal_kh_by_deformation_method( &
               dt, iblock%mesh%xlen, iblock%mesh%ylen, &
               iblock%u(:, :, k), iblock%v(:, :, k), &
               iblock%kx(:, :, k), iblock%ky(:, :, k), iblock%mesh%delta**2)
         else
            call cal_kh_by_deformation_method( &
               dt, iblock%mesh%xlen, iblock%mesh%ylen, &
               iblock%u(:, :, k), iblock%v(:, :, k), &
               iblock%kx(:, :, k), iblock%ky(:, :, k))
         end if
      end do

      do j = tile%jbs, tile%jbe
         do i = tile%ibs, tile%ibe
            u_mass = (iblock%u(i, j, :) + iblock%u(i - 1, j, :))/2._fp
            v_mass = (iblock%v(i, j, :) + iblock%v(i, j - 1, :))/2._fp

            call cal_pbl_param( &
               iblock%TSK(i, j), iblock%T(i, j, 1), &
               iblock%PSFC(i, j)/100._fp, iblock%P(i, j, 1)/100._fp, &
               iblock%dz(i, j, 1), &
               sqrt(iblock%u(i, j, 1)**2 + iblock%v(i, j, 1)**2), &
               iblock%mete2d(i, j, iblock%m2d_idx%get('z0')), iblock%PBL(i, j), &
               iblock%Ri(i, j), iblock%ustar(i, j), &
               iblock%RMOL(i, j), iblock%wstar(i, j))

            call cal_Kz_by_YSU( &
               iblock%PBL(i, j), iblock%Ri(i, j), iblock%ustar(i, j), &
               iblock%RMOL(i, j), iblock%wstar(i, j), iblock%zt(i, j, :), &
               iblock%dz(i, j, :), u_mass, v_mass, iblock%thetav(i, j, :), &
               iblock%kz(i, j, :))
         end do
      end do
   end subroutine diagnose_meteorology

end module mod_mete_diagnostic
