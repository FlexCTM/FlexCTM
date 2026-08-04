module mod_mete_diagnostic
   !! 基于 FlexCTM 标准气象数据统一计算数值过程所需的诊断量。
   use mod_const, only: fp
   use mod_block, only: block_type

   use parallel, only: tile_type, fill_halo
   use ysu, only: cal_pbl_param, cal_Kz_by_YSU
   use diffusion, only: cal_kh_by_deformation_method

   implicit none
   private

   public :: diagnose_meteorology, prepare_meteorology

contains

   subroutine prepare_meteorology(tile, iblock, factor, input_interval, dt)
      !! 将相邻输入时次线性插值到目标时刻，并更新该时刻的公共诊断量。
      type(tile_type), intent(in) :: tile
      type(block_type), intent(inout) :: iblock
      real(fp), intent(in) :: factor !! 前一输入时次的权重；后一时次的权重为 1-factor。
      real(fp), intent(in) :: input_interval !! 相邻气象输入时次的间隔 [s]。
      real(fp), intent(in) :: dt     !! 诊断算法使用的当前 domain 时间步长 [s]。

      integer :: zt_index

      iblock%mete2d = factor*iblock%mete2d_1 + (1._fp - factor)*iblock%mete2d_2
      iblock%mete3d = factor*iblock%mete3d_1 + (1._fp - factor)*iblock%mete3d_2
      zt_index = iblock%m3d_idx%get('zt')
      iblock%dzdt = (iblock%mete3d_2(:, :, :, zt_index) - iblock%mete3d_1(:, :, :, zt_index))/input_interval

      call fill_halo(tile, iblock%u)
      if (tile%at_north_pole .or. tile%at_south_pole) then
         call fill_halo(tile, iblock%v, is_v=.false.)
      else
         call fill_halo(tile, iblock%v)
      end if
      call diagnose_meteorology(tile, iblock, dt)
      call fill_halo(tile, iblock%rho)
      call fill_halo(tile, iblock%volume)
   end subroutine prepare_meteorology

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
            call cal_kh_by_deformation_method( dt, iblock%mesh%xlen, iblock%mesh%ylen, iblock%u(:, :, k), iblock%v(:, :, k), &
               iblock%kx(:, :, k), iblock%ky(:, :, k), iblock%mesh%delta**2)
         else
            call cal_kh_by_deformation_method( dt, iblock%mesh%xlen, iblock%mesh%ylen, iblock%u(:, :, k), iblock%v(:, :, k), &
               iblock%kx(:, :, k), iblock%ky(:, :, k))
         end if
      end do

      do j = tile%jbs, tile%jbe
         do i = tile%ibs, tile%ibe
            u_mass = (iblock%u(i, j, :) + iblock%u(i - 1, j, :))/2._fp
            v_mass = (iblock%v(i, j, :) + iblock%v(i, j - 1, :))/2._fp

            call cal_pbl_param( iblock%TSK(i, j), iblock%T(i, j, 1), iblock%PSFC(i, j)/100._fp, iblock%P(i, j, 1)/100._fp, &
               iblock%dz(i, j, 1), sqrt(iblock%u(i, j, 1)**2 + iblock%v(i, j, 1)**2), &
               iblock%mete2d(i, j, iblock%m2d_idx%get('z0')), iblock%PBL(i, j), iblock%Ri(i, j), iblock%ustar(i, j), &
               iblock%RMOL(i, j), iblock%wstar(i, j))

            call cal_Kz_by_YSU( iblock%PBL(i, j), iblock%Ri(i, j), iblock%ustar(i, j), &
               iblock%RMOL(i, j), iblock%wstar(i, j), iblock%zt(i, j, :), &
               iblock%dz(i, j, :), u_mass, v_mass, iblock%thetav(i, j, :), iblock%kz(i, j, :))
         end do
      end do
   end subroutine diagnose_meteorology

end module mod_mete_diagnostic
