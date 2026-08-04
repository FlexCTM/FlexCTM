module mod_error
   !! 应用级不可恢复错误的统一出口。
   use, intrinsic :: iso_fortran_env, only: error_unit
   use mpi, only: MPI_ABORT, MPI_COMM_RANK, MPI_COMM_WORLD, MPI_FINALIZED, &
                  MPI_INITIALIZED, MPI_SUCCESS

   implicit none
   private

   public :: fatal_error

contains

   subroutine fatal_error(message, exit_code)
      character(len=*), intent(in) :: message !! User-facing cause and context. / 面向用户的错误原因与上下文。
      integer, optional, intent(in) :: exit_code !! Nonzero process exit code; default 1. / 非零进程退出码，默认为 1。

      integer :: code       !! Effective exit code. / 实际使用的退出码。
      integer :: ierr       !! Status from MPI lifecycle queries. / MPI 生命周期查询状态。
      integer :: rank       !! Rank in MPI_COMM_WORLD; only rank zero logs. / 全局通信器 rank，仅 rank 0 输出。
      logical :: initialized !! MPI has completed initialization. / MPI 是否已完成初始化。
      logical :: finalized   !! MPI has already been finalized. / MPI 是否已经结束。

      code = 1
      if (present(exit_code)) code = exit_code

      initialized = .false.
      finalized = .false.
      call MPI_INITIALIZED(initialized, ierr)
      if (ierr == MPI_SUCCESS .and. initialized) call MPI_FINALIZED(finalized, ierr)

      if (initialized .and. .not. finalized .and. ierr == MPI_SUCCESS) then
         rank = 0
         call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierr)
         if (ierr /= MPI_SUCCESS .or. rank == 0) write (error_unit, '(a)') 'FATAL: '//trim(message)
         flush (error_unit)
         call MPI_ABORT(MPI_COMM_WORLD, code, ierr)
      else
         write (error_unit, '(a)') 'FATAL: '//trim(message)
         flush (error_unit)
      end if

      error stop code
   end subroutine fatal_error

end module mod_error
