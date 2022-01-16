! Copyright 2021 Matthew Zettergren

! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!   http://www.apache.org/licenses/LICENSE-2.0

! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.

module gemini3d

use, intrinsic :: iso_c_binding, only : c_char, c_null_char, c_int, c_bool, c_float
use gemini_cli, only : cli
use gemini_init, only : find_config, check_input_files
use phys_consts, only: wp,debug,lnchem,lwave,lsp
use meshobj, only: curvmesh
use config, only: gemini_cfg
use collisions, only: conductivities
use pathlib, only : expanduser
use grid, only: grid_size,lx1,lx2,lx3
use config, only : read_configfile

implicit none (type, external)
private
public :: c_params, cli_config_gridsize, gemini_alloc, gemini_dealloc

type, bind(C) :: c_params
  !! this MUST match gemini3d.h and libgemini.f90 exactly including order
  logical(c_bool) :: fortran_cli, debug, dryrun
  character(kind=c_char) :: out_dir(1000)
  !! .ini [base]
  integer(c_int) :: ymd(3)
  real(kind=c_float) :: UTsec0, tdur, dtout, activ(3), tcfl, Teinf
  !! .ini
end type c_params

contains
  !> read command line args, config file, and size of grid
  subroutine cli_config_gridsize(p,cfg,lid2in,lid3in)
    type(c_params), intent(in) :: p
    type(gemini_cfg), intent(inout) :: cfg
    integer, intent(inout) :: lid2in,lid3in
    character(size(p%out_dir)) :: buf
    integer :: i

    !> command line interface    
    if(p%fortran_cli) then
      call cli(cfg, lid2in, lid3in, debug)
    else
      buf = "" !< ensure buf has no garbage characters
  
      do i = 1, len(buf)
        if (p%out_dir(i) == c_null_char) exit
        buf(i:i) = p%out_dir(i)
      enddo
      cfg%outdir = expanduser(buf)
  
      cfg%dryrun = p%dryrun
      debug = p%debug
    endif

    !> read the config input file 
    call find_config(cfg)
    call read_configfile(cfg, verbose=.false.)
    call check_input_files(cfg)
    
    !> read the size out of the grid file, store in module variables
    call grid_size(cfg%indatsize)
  end subroutine cli_config_gridsize


  !> allocate arrays
  ! FIXME: eventually needs to be a single block of memory
  subroutine gemini_alloc(cfg,ns,vs1,vs2,vs3,Ts,rhov2,rhov3,B1,B2,B3,v1,v2,v3,rhom,E1,E2,E3,J1,J2,J3,Phi,nn,Tn,vn1,vn2,vn3,iver)
    type(gemini_cfg), intent(in) :: cfg
    real(wp), dimension(:,:,:,:), allocatable, intent(inout) :: ns,vs1,vs2,vs3,Ts
    real(wp), dimension(:,:,:), allocatable, intent(inout) :: rhov2,rhov3,B1,B2,B3,v1,v2,v3,rhom,E1,E2,E3,J1,J2,J3,Phi
    real(wp), dimension(:,:,:,:), allocatable, intent(inout) :: nn
    real(wp), dimension(:,:,:), allocatable, intent(inout) :: Tn,vn1,vn2,vn3
    real(wp), dimension(:,:,:), allocatable, intent(inout) :: iver

    allocate(ns(-1:lx1+2,-1:lx2+2,-1:lx3+2,lsp),vs1(-1:lx1+2,-1:lx2+2,-1:lx3+2,lsp),vs2(-1:lx1+2,-1:lx2+2,-1:lx3+2,lsp), &
      vs3(-1:lx1+2,-1:lx2+2,-1:lx3+2,lsp), Ts(-1:lx1+2,-1:lx2+2,-1:lx3+2,lsp))
    allocate(rhov2(-1:lx1+2,-1:lx2+2,-1:lx3+2),rhov3(-1:lx1+2,-1:lx2+2,-1:lx3+2),B1(-1:lx1+2,-1:lx2+2,-1:lx3+2), &
             B2(-1:lx1+2,-1:lx2+2,-1:lx3+2),B3(-1:lx1+2,-1:lx2+2,-1:lx3+2))
    allocate(v1(-1:lx1+2,-1:lx2+2,-1:lx3+2),v2(-1:lx1+2,-1:lx2+2,-1:lx3+2), &
             v3(-1:lx1+2,-1:lx2+2,-1:lx3+2),rhom(-1:lx1+2,-1:lx2+2,-1:lx3+2))
    allocate(E1(lx1,lx2,lx3),E2(lx1,lx2,lx3),E3(lx1,lx2,lx3),J1(lx1,lx2,lx3),J2(lx1,lx2,lx3),J3(lx1,lx2,lx3))
    allocate(Phi(lx1,lx2,lx3))
    allocate(nn(lx1,lx2,lx3,lnchem),Tn(lx1,lx2,lx3),vn1(lx1,lx2,lx3), vn2(lx1,lx2,lx3),vn3(lx1,lx2,lx3))

     !> space for integrated volume emission rates
    if (cfg%flagglow /= 0) then
      allocate(iver(lx2,lx3,lwave))
      iver = 0
    end if 
  end subroutine gemini_alloc


  !> deallocate arrays
  subroutine gemini_dealloc(cfg,ns,vs1,vs2,vs3,Ts,rhov2,rhov3,B1,B2,B3,v1,v2,v3,rhom,E1,E2,E3,J1,J2,J3,Phi,nn,Tn,vn1,vn2,vn3,iver)
    type(gemini_cfg), intent(in) :: cfg
    real(wp), dimension(:,:,:,:), allocatable, intent(inout) :: ns,vs1,vs2,vs3,Ts
    real(wp), dimension(:,:,:), allocatable, intent(inout) :: rhov2,rhov3,B1,B2,B3,v1,v2,v3,rhom,E1,E2,E3,J1,J2,J3,Phi
    real(wp), dimension(:,:,:,:), allocatable, intent(inout) :: nn
    real(wp), dimension(:,:,:), allocatable, intent(inout) :: Tn,vn1,vn2,vn3
    real(wp), dimension(:,:,:), allocatable, intent(inout) :: iver

    deallocate(ns,vs1,vs2,vs3,Ts)
    deallocate(rhov2,rhov3,B1,B2,B3)
    deallocate(v1,v2,v3,rhom)
    deallocate(E1,E2,E3,J1,J2,J3)
    deallocate(Phi)
    deallocate(nn,Tn,vn1,vn2,vn3)

     !> space for integrated volume emission rates
    if (cfg%flagglow /= 0) then
      deallocate(iver)
    end if 
  end subroutine gemini_dealloc
end module gemini3d
