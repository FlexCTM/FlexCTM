module mod_boundary
  !! 区域边界条件
   use mod_block, only: block_type

   use parallel, only: tile_type, west, east, south, north

   implicit none

   private

   public read_domain_boundary

contains

   subroutine read_domain_boundary(tile, iblock, filename)
  !! 更新区域边界条件
      type(tile_type), intent(in) :: tile     !! 切片信息
      type(block_type), intent(inout) :: iblock   !! 数据块
      character(len=*), optional, intent(in) :: filename !! 边界文件

      if (iblock%edges(west)%is_edge) then
         iblock%edges(west)%bc = 0
      end if
      if (iblock%edges(east)%is_edge) then
         iblock%edges(east)%bc = 0
      end if
      if (iblock%edges(south)%is_edge) then
         iblock%edges(south)%bc = 0
      end if
      if (iblock%edges(north)%is_edge) then
         iblock%edges(north)%bc = 0
      end if

   end subroutine read_domain_boundary

end module mod_boundary
