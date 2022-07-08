function(setup_gemini_test name TIMEOUT)

# --- setup test
cmake_path(SET out_dir ${PROJECT_BINARY_DIR}/${name})
cmake_path(SET ref_root ${PROJECT_SOURCE_DIR}/test_data/compare)
cmake_path(SET ref_dir ${ref_root}/${name})
cmake_path(SET arc_json_file ${PROJECT_BINARY_DIR}/ref_data.json)

add_test(NAME ${name}:download
COMMAND ${CMAKE_COMMAND}
  -Dname=${name}
  -Doutdir:PATH=${out_dir}
  -Drefroot:PATH=${ref_root}
  -Darc_json_file:FILEPATH=${arc_json_file}
  -P ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/download.cmake
)
set_tests_properties(${name}:download PROPERTIES
FIXTURES_REQUIRED internet_fxt
FIXTURES_SETUP ${name}:download_fxt
RESOURCE_LOCK download_lock  # avoid anti-leeching transient failures
LABELS download
TIMEOUT 180
)

# construct command
set(test_cmd gemini3d.run ${out_dir})
if(name MATCHES "_cpp$")
  list(APPEND test_cmd -exe $<TARGET_FILE:gemini_c.bin>)
else()
  list(APPEND test_cmd -exe $<TARGET_FILE:gemini.bin>)
endif()
if(mpi)
  list(APPEND test_cmd -mpiexec ${MPIEXEC_EXECUTABLE})
endif()

add_test(NAME gemini:hdf5:${name}:dryrun
COMMAND ${test_cmd} -dryrun
)

set_tests_properties(gemini:hdf5:${name}:dryrun PROPERTIES
TIMEOUT 60
FIXTURES_SETUP hdf5:${name}:dryrun
FIXTURES_REQUIRED "gemini_exe_fxt;${name}:download_fxt"
)


add_test(NAME gemini:hdf5:${name} COMMAND ${test_cmd})

set_tests_properties(gemini:hdf5:${name} PROPERTIES
TIMEOUT ${TIMEOUT}
FIXTURES_REQUIRED hdf5:${name}:dryrun
FIXTURES_SETUP hdf5:${name}:run_fxt
)

dll_test_path("ffilesystem::filesystem;gemini3d;h5fortran::h5fortran;HDF5::HDF5" "gemini:hdf5:${name}:dryrun;gemini:hdf5:${name}")

set_tests_properties(gemini:hdf5:${name}:dryrun gemini:hdf5:${name} PROPERTIES
RESOURCE_LOCK cpu_mpi
REQUIRED_FILES ${out_dir}/inputs/config.nml
LABELS core
WORKING_DIRECTORY $<TARGET_FILE_DIR:gemini.bin>
)
# WORKING_DIRECTORY is needed for tests like HWM14 that need data files in binary directory.

compare_gemini_output(${name} ${out_dir} ${ref_dir})

endfunction(setup_gemini_test)


function(setup_magcalc_test name)

cmake_path(SET out_dir ${PROJECT_BINARY_DIR}/${name})

add_test(NAME magcalc:${name}:setup
COMMAND ${Python_EXECUTABLE} -m gemini3d.magcalc ${out_dir}
)
set_tests_properties(magcalc:${name}:setup PROPERTIES
FIXTURES_REQUIRED hdf5:${name}:run_fxt
FIXTURES_SETUP magcalc:${name}:setup
TIMEOUT 30
DISABLED $<NOT:$<BOOL:${PYGEMINI_DIR}>>
)

add_test(NAME magcalc:${name} COMMAND magcalc.run ${out_dir})
set_tests_properties(magcalc:${name} PROPERTIES
RESOURCE_LOCK cpu_mpi
FIXTURES_REQUIRED magcalc:${name}:setup
LABELS core
TIMEOUT 60
DISABLED $<NOT:$<BOOL:${PYGEMINI_DIR}>>
)
dll_test_path("h5fortran::h5fortran;HDF5::HDF5" magcalc:${name})

endfunction(setup_magcalc_test)


add_test(NAME internetConnectivity
COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_LIST_DIR}/connectivity.cmake)
set_tests_properties(internetConnectivity PROPERTIES
TIMEOUT 10
FIXTURES_SETUP internet_fxt
)
