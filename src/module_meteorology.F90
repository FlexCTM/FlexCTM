module mod_meteorology
   !! 根据运行配置在 WRF 和 MOCK 气象数据源之间调度。
   use mod_error, only: fatal_error
   use mod_block, only: block_type
   use mod_mete_type, only: mete_mapping_table_type
   use mod_meteorology_wrf, only: read_wrf_field => read_mete_field
   use mod_meteorology_wrf, only: read_wrf_static => read_mete_static
   use mod_meteorology_mock, only: generate_mock_meteorology, generate_mock_static

   use parallel, only: process_type, domain_type, tile_type

   implicit none
   private

   public :: read_mete_field, read_mete_static

contains

   subroutine read_mete_field(source, proc, domain, tile, iblock, filename, mapping)
      character(len=*), intent(in) :: source     !! 数据源名称：wrf 或 mock。
      type(process_type), intent(in) :: proc     !! 当前进程。
      type(domain_type), intent(in) :: domain   !! 当前区域。
      type(tile_type), intent(in) :: tile       !! 当前数据切片。
      type(block_type), intent(inout) :: iblock !! 当前数据块。
      character(len=*), intent(in) :: filename  !! 外部气象文件；MOCK 模式忽略。
      type(mete_mapping_table_type), optional, intent(in) :: mapping !! 数据集映射表。

      select case (trim(source))
      case ('wrf')
         if (.not. present(mapping)) call fatal_error('WRF meteorology requires a mapping table')
         call read_wrf_field(proc, domain, tile, iblock, mapping, filename)
      case ('mock')
         call generate_mock_meteorology(iblock)
      case default
         call fatal_error('unsupported meteorology source: "'//trim(source)//'"')
      end select
   end subroutine read_mete_field

   subroutine read_mete_static(source, proc, domain, tile, iblock, filename)
      character(len=*), intent(in) :: source     !! 数据源名称：wrf 或 mock。
      type(process_type), intent(in) :: proc     !! 当前进程。
      type(domain_type), intent(in) :: domain   !! 当前区域。
      type(tile_type), intent(in) :: tile       !! 当前数据切片。
      type(block_type), intent(inout) :: iblock !! 当前数据块。
      character(len=*), intent(in) :: filename  !! 外部气象文件；MOCK 模式忽略。

      select case (trim(source))
      case ('wrf')
         call read_wrf_static(proc, domain, tile, iblock, filename)
      case ('mock')
         call generate_mock_static(iblock)
      case default
         call fatal_error('unsupported meteorology source: "'//trim(source)//'"')
      end select
   end subroutine read_mete_static

end module mod_meteorology
