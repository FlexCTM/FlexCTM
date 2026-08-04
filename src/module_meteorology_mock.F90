module mod_meteorology_mock
   !! 为单元测试和无外部气象文件运行生成确定性的标准气象场。
   use mod_const, only: fp, P00, Rd, R_cp
   use mod_block, only: block_type

   implicit none
   private

   public :: generate_mock_meteorology, generate_mock_static

contains

   subroutine generate_mock_meteorology(iblock)
      !! 生成适合全球输送测试的纬向、经向和垂直结构。
      type(block_type), intent(inout) :: iblock !! 待填充的数据块。

      real(fp), parameter :: pi = acos(-1._fp)
      real(fp) :: height, latitude, surface_temperature
      integer :: i, j, k

      do j = 1, iblock%ny
         do i = 1, iblock%nx
            latitude = iblock%mesh%mlat(i, j)*pi/180._fp
            surface_temperature = 300._fp - 35._fp*sin(latitude)**2
            iblock%PBL(i, j) = 400._fp + 900._fp*cos(latitude)**2
            iblock%PSFC(i, j) = P00*exp(-iblock%terrain(i, j)/8000._fp)
            iblock%TSK(i, j) = surface_temperature
            iblock%mete2d(i, j, iblock%m2d_idx%get('z0')) = &
               0.03_fp + 0.17_fp*cos(latitude)**2
            do k = 1, iblock%nz
               height = 500._fp*real(k, fp)
               iblock%u(i, j, k) = 5._fp + &
                  25._fp*exp(-((abs(iblock%mesh%mlat(i, j)) - 45._fp)/15._fp)**2)
               iblock%v(i, j, k) = -2._fp*sin(2._fp*latitude)*exp(-height/8000._fp)
               iblock%w(i, j, k) = 0._fp
               iblock%dz(i, j, k) = 500._fp
               iblock%zt(i, j, k) = height
               iblock%P(i, j, k) = iblock%PSFC(i, j)*exp(-height/8000._fp)
               iblock%T(i, j, k) = max(215._fp, surface_temperature - 0.0065_fp*height)
               iblock%rho(i, j, k) = iblock%P(i, j, k)/(Rd*iblock%T(i, j, k))
               iblock%thetav(i, j, k) = &
                  iblock%T(i, j, k)*(P00/iblock%P(i, j, k))**R_cp
            end do
         end do
      end do
   end subroutine generate_mock_meteorology

   subroutine generate_mock_static(iblock)
      !! 生成光滑解析地形，避免依赖外部静态数据。
      type(block_type), intent(inout) :: iblock
      real(fp) :: latitude, longitude
      integer :: i, j

      do j = 1, iblock%ny
         do i = 1, iblock%nx
            latitude = iblock%mesh%mlat(i, j)
            longitude = iblock%mesh%mlon(i, j)
            iblock%terrain(i, j) = &
               1800._fp*exp(-((longitude - 85._fp)/18._fp)**2 - &
                             ((latitude - 32._fp)/10._fp)**2) + &
               900._fp*exp(-((longitude + 70._fp)/20._fp)**2 - &
                            ((latitude + 20._fp)/12._fp)**2)
         end do
      end do
   end subroutine generate_mock_static

end module mod_meteorology_mock
