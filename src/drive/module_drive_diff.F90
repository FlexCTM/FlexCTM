module mod_drive_diff
   !! 扩散驱动模块
   use mod_const, only: fp
   use mod_block, only: block_type

   use parallel, only: tile_type, fill_halo
   use diffusion, only: cal_cfl_time_step, hdiff1d_by_k_theory, vdiff_by_k_theory

   implicit none

   private
   public drive_hdiff_by_k_theory, drive_vdiff_by_k_theory

contains

   subroutine drive_hdiff_by_k_theory(tile, iblock, dt)
      !! 水平扩散驱动程序
      type(tile_type), intent(in) :: tile       !! 切片信息
      type(block_type), intent(inout) :: iblock !! 数据块
      real(fp), intent(in) :: dt                !! 积分时间

      real(fp) :: sdt !! delta time of sub-time step
      integer :: i, j, k, n, it, nt
      real(fp) :: dc(iblock%nx, iblock%ny) !! 浓度变化

      associate (vv => iblock%volume, c => iblock%chem3d, u => iblock%u, v => iblock%v, &
                 t => iblock%twindow, xlen => iblock%mesh%xlen, ylen => iblock%mesh%ylen)
         ! y 方向扩散
         do n = 1, iblock%chem_meta%nvar ! 不同污染物
            if (.not. iblock%chem_meta%vars(n)%diffused) cycle
            do k = 1, size(v, 3) ! 不同垂直层
               do i = tile%ibs, tile%ibe
                  call cal_cfl_time_step(ylen(i, :), iblock%ky(i, :, k), dt, sdt, nt) ! 根据局地扩散系数确定稳定时间步长。
                  do it = 1, nt ! 确保满足CFL条件
                     call hdiff1d_by_k_theory(sdt, ylen(i, :), iblock%ky(i, :, k), &
                                              iblock%rho(i, :, k), c(i, :, k, n, t), &
                                              dc(i, :), vv(i, :, k))
                  end do
               end do
            end do
         end do

         ! 保证一致性
         call fill_halo(tile, c(:, :, :, :, t)) ! 完成 y 方向扩散后更新 halo。

         ! x方向扩散
         do n = 1, iblock%chem_meta%nvar ! 不同污染物
            if (.not. iblock%chem_meta%vars(n)%diffused) cycle
            do k = 1, size(vv, 3)
               do j = tile%jbs, tile%jbe
                  call cal_cfl_time_step(xlen(:, j), iblock%kx(:, j, k), dt, sdt, nt) ! 根据局地扩散系数确定稳定时间步长。
                  do it = 1, nt ! 确保满足CFL条件
                     call hdiff1d_by_k_theory(sdt, xlen(:, j), iblock%kx(:, j, k), &
                                              iblock%rho(:, j, k), c(:, j, k, n, t), &
                                              dc(:, j), vv(:, j, k))
                  end do
               end do
            end do
         end do

      end associate

   end subroutine drive_hdiff_by_k_theory

   subroutine drive_vdiff_by_k_theory(tile, iblock, dt)
      !! 垂直扩散驱动程序
      type(tile_type), intent(in) :: tile       !! 切片信息
      type(block_type), intent(inout) :: iblock !! 数据块
      real(fp), intent(in) :: dt                !! 积分时间

      integer :: i, j, n

      associate (c => iblock%chem3d, t => iblock%twindow)
         do n = 1, iblock%chem_meta%nvar ! 不同污染物
            if (.not. iblock%chem_meta%vars(n)%diffused) cycle
            do j = iblock%jbs, iblock%jbe
               do i = iblock%ibs, iblock%ibe
                  call vdiff_by_k_theory(dt, iblock%kz(i, j, :), &
                                        iblock%dz(i, j, :), &
                                        iblock%rho(i, j, :), &
                                        c(i, j, :, n, t))
               end do
            end do
         end do
      end associate

   end subroutine drive_vdiff_by_k_theory

end module mod_drive_diff
