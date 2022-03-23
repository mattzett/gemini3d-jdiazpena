#include <iostream>

#include "gemini3d.h"

// top-level module calls for gemini simulation
void gemini_main(struct params* ps, int* plid2in, int* plid3in){
  int ierr;
  int lx1,lx2,lx3;
  int lx2all,lx3all;
  int lsp;
  double UTsec;
  int ymd[3];
  double* fluidvars;
  double* fluidauxvars;
  double* electrovars;    // pointers modifiable by fortran
  double t, dt=1e-6;
  double tout, tneuBG, tglowout, tdur, tmilestone=0;
  double tstart, tfin;
  int it, iupdate;
  int flagoutput;
  double v2grid,v3grid;
  bool first,flagneuBG;
  int flagdneu;
  double dtneu,dtneuBG;
  int myid,lid;
  void fluid_adv(double*, double*, int*, double*, bool*, int*, int*);

  /* Basic setup */
  mpisetup_C();                               // organize mpi workers
  mpiparms_C(&myid,&lid);                     // information about worker number, etc.
  cli_config_gridsize(ps,plid2in,plid3in);    // handling of input data, create internal fortran type with parameters for run
  get_fullgrid_size_C(&lx1,&lx2all,&lx3all);  // read input file that has the grid size information and set it
  init_procgrid(&lx2all,&lx3all,plid2in,plid3in);            // compute process grid for this run
  get_config_vars_C(&flagneuBG,&flagdneu,&dtneuBG,&dtneu);   // export config type properties as C variables, for use in main

  /* Get input grid from file */
  read_grid_C();                              // read the input grid from file, storage as fortran module object

  /* Main needs to know the grid sizes and species numbers */
  get_subgrid_size_C(&lx1,&lx2,&lx3);     // once grid is input we need to know the subgrid sizes based on no of workers and overall size
  get_species_size_C(&lsp);               // so main knows the number of species used

  /* Allocate memory and get pointers to blocks of data */
  gemini_alloc(&fluidvars,&fluidauxvars,&electrovars);    // allocate space in fortran modules for data
  outdir_fullgridvaralloc(&lx1,&lx2all,&lx3all);          // create output directory and allocate some module space for potential

  /* initialize state variables from input file */
  get_initial_state(&UTsec,&ymd[0],&tdur);
  set_start_values(&it,&t,&tout,&tglowout,&tneuBG);

  /* initialize other file input data */
  std::cout << " Initializing electric field input data..." << std::endl;
  init_Efieldinput_C(&dt,&t,&ymd[0],&UTsec);
  pot2perpfield_C();
  BGfield_Lagrangian(&v2grid,&v3grid);
  std::cout << " Initialize precipitation input data..." << std::endl;
  init_precipinput_C(&dt,&t,&ymd[0],&UTsec);
  std::cout << " Initialize neutral background and input files..." << std::endl;
  msisinit_C();
  init_neutralBG_C(&dt,&t,&ymd[0],&UTsec,&v2grid,&v3grid);
  init_neutralperturb_C(&dt,&ymd[0],&UTsec);

  /* Compute initial drift velocity */
  get_initial_drifts();

  /* Control console printing for, actually superfluous FIXME */
  set_update_cadence(&iupdate);

  while(t<tdur){
    dt_select_C(&it,&t,&tout,&tglowout,&dt);

    std::cout << " ...Selected time step (seconds) " << dt << std::endl;

    // neutral data
    if (it!=1 && flagneuBG && t>tneuBG){
      neutral_atmos_winds_C(&ymd[0],&UTsec);
      neutral_atmos_wind_update_C(&v2grid,&v3grid);
      tneuBG+=dtneuBG;
      std::cout << " Computed neutral background..." << std::endl;
    }
    if (flagdneu==1){
      neutral_perturb_C(&dt,&t,&ymd[0],&UTsec,&v2grid,&v3grid);
      std::cout << " Computed neutral perturbations..." << std::endl;
    }

    // call electrodynamics solution
    std::cout << " Start electro solution..." << std::endl;
    electrodynamics_C(&it,&t,&dt,&ymd[0],&UTsec);
    std::cout << " Computed electrodynamics solutions..." << std::endl;

    // advance the fluid state variables
    first=it==1;
    fluid_adv(&t,&dt,&ymd[0],&UTsec,&first,&lsp,&myid);
    std::cout << " Computed fluid update..." << std::endl;

    check_finite_output_C(&t);
    it+=1; t+=dt;
    dateinc_C(&dt,&ymd[0],&UTsec);
    std::cout << " Time step %d finished: " << it << " " << ymd[0] << " " << ymd[1] << " " << ymd[2] << " " << UTsec << " " << t << std::endl;
    check_dryrun();
    check_fileoutput(&t,&tout,&tglowout,&tmilestone,&flagoutput,&ymd[0],&UTsec);
    std::cout << " Output cadence variables:  " << tout << " " << tglowout << " " << tmilestone << std::endl;
  }

  /* Call deallocation procedures */
  gemini_dealloc(&fluidvars,&fluidauxvars,&electrovars);
  clear_neuBG_C();
  clear_dneu_C();

}
