using Test, Pkg

export mpirun, deactivate_multithreading, run_petsc_ex

# ensure that we use the correct version of the package 
Pkg.add(url="https://github.com/boriskaus/SuperLU_DIST_jll.jl")
using SuperLU_DIST_jll

Pkg.add(url="https://github.com/boriskaus/PETSc_jll.jl")
using PETSc_jll

# Show the host platform (debug info)
@show  PETSc_jll.host_platform
@show  names(PETSc_jll)

#setup MPI
const mpiexec = if isdefined(PETSc_jll,:MPICH_jll)
    PETSc_jll.MPICH_jll.mpiexec()
elseif isdefined(PETSc_jll,:MicrosoftMPI_jll) 
    PETSc_jll.MicrosoftMPI_jll.mpiexec()
elseif isdefined(PETSc_jll,:OpenMPI_jll) 
    PETSc_jll.OpenMPI_jll.mpiexec()
elseif isdefined(PETSc_jll,:MPItrampoline_jll) 
    PETSc_jll.MPItrampoline_jll.mpiexec()
else
    println("Be careful! No MPI library detected; parallel runs won't work")
    nothing
end
mpirun = setenv(mpiexec, PETSc_jll.JLLWrappers.JLLWrappers.LIBPATH_env=>PETSc_jll.LIBPATH[]);


function deactivate_multithreading(cmd::Cmd)
    # multithreading of the BLAS libraries that is installed by default with the julia BLAS
    # does not work well. Switch that off:
    cmd = addenv(cmd,"OMP_NUM_THREADS"=>1)
    cmd = addenv(cmd,"VECLIB_MAXIMUM_THREADS"=>1)

    return cmd
end

"""
    r = run_petsc_ex(ParamFile::String, cores::Int64=1, ex="ex4", args::String=""; wait=true, deactivate_multithreads=true, mpi_single_core=false)
runs a petsc example
"""
function run_petsc_ex(args::Cmd=``, cores::Int64=1, ex="ex4", ; wait=true, deactivate_multithreads=true, mpi_single_core=false)
        
    if cores==1 & !mpi_single_core
        # Run LaMEM on a single core, which does not require a working MPI
        if ex=="ex4"
            cmd = `$(PETSc_jll.ex4()) $args`
        elseif ex=="ex42"
            cmd = `$(PETSc_jll.ex42())  $args`
        elseif ex=="ex19"
            cmd = `$(PETSc_jll.ex19())  $args`
        else
            error("unknown example")
        end
        if deactivate_multithreads
            cmd = deactivate_multithreading(cmd)
        end

        r = run(cmd, wait=wait);
    else
        # create command-line object
        if ex=="ex4"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex4_path) $args`
        elseif ex=="ex42"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex42_path) $args`
        elseif ex=="ex19"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex19_int64_deb_path) $args`
        else
            error("unknown example")
        end
        if deactivate_multithreads
            cmd = deactivate_multithreading(cmd)
        end

        # Run example in parallel
        r = run(cmd, wait=wait);
    end

    return r
end


test_suitesparse = false
test_superlu_dist = false
test_mumps = false

@testset "ex19, ex42, ex4" begin

    # Note: ex19 is thew default test that PETSc performs @ the end of the installation process
    @testset "ex19 1: iterative" begin
        args = `-da_refine 3 -pc_type mg -ksp_type fgmres`;
        r = run_petsc_ex(args, 1, "ex19")
        @test r.exitcode == 0
    end
    
    # testex19_mpi:
    @testset "ex19 2: mpi" begin
        args = `-da_refine 3 -pc_type mg -ksp_type fgmres`;
        r = run_petsc_ex(args, 2, "ex19")
        @test r.exitcode == 0
    end

    # runex19_fieldsplit_mumps
    @testset "ex19 2: fieldsplit_mumps" begin
        if test_mumps
            args = `-pc_type fieldsplit -pc_fieldsplit_block_size 4 -pc_fieldsplit_type SCHUR -pc_fieldsplit_0_fields 0,1,2 -pc_fieldsplit_1_fields 3 -fieldsplit_0_pc_type lu -fieldsplit_1_pc_type lu -snes_monitor_short -ksp_monitor_short  -fieldsplit_0_pc_factor_mat_solver_type mumps -fieldsplit_1_pc_factor_mat_solver_type mumps`;
            r = run_petsc_ex(args, 2, "ex19")
            @test r.exitcode == 0
        end
    end

    # runex19_superlu_dist
    @testset "ex19 2: fieldsplit_superlu_dist" begin
        if test_superlu_dist
            #args = `-da_grid_x 20 -da_grid_y 20 -pc_type lu -pc_factor_mat_solver_type superlu_dist`;
            args = `-pc_type fieldsplit -pc_fieldsplit_block_size 4 -pc_fieldsplit_type SCHUR -pc_fieldsplit_0_fields 0,1,2 -pc_fieldsplit_1_fields 3 -fieldsplit_0_pc_type lu -fieldsplit_1_pc_type lu -snes_monitor_short -ksp_monitor_short  -fieldsplit_0_pc_factor_mat_solver_type superlu_dist -fieldsplit_1_pc_factor_mat_solver_type superlu_dist`;
            
            r = run_petsc_ex(args, 2, "ex19")
            @test r.exitcode == 0
        end
    end
    
    
    # runex19_suitesparse
    @testset "ex19 1: suitesparse" begin
        if test_suitesparse
            args = `-da_refine 3 -snes_monitor_short -pc_type lu -pc_factor_mat_solver_type umfpack`;
            r = run_petsc_ex(args, 1, "ex19")
            @test r.exitcode == 0
        end
    end
    
    @testset "ex42 1: serial" begin
        args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type lu`;
        r = run_petsc_ex(args, 1, "ex42")
        @test r.exitcode == 0
    end
    
    @testset "ex42 2: mumps" begin
        if test_mumps
            args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type lu -stokes_pc_factor_mat_solver_type mumps `;
            r = run_petsc_ex(args, 2, "ex42")
            @test r.exitcode == 0
        end
    end
    
    @testset "ex42 3: redundant lu" begin
        args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type redundant -stokes_redundant_pc_type lu`;
        r = run_petsc_ex(args, 3, "ex42")
        @test r.exitcode == 0
    end

    @testset "ex42 6: bddc_stokes" begin
        args = `-mx 5 -my 4 -mz 3 -stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type bddc -dm_mat_type is -stokes_pc_bddc_dirichlet_pc_type svd -stokes_pc_bddc_neumann_pc_type svd -stokes_pc_bddc_coarse_redundant_pc_type svd`;
        r = run_petsc_ex(args, 6, "ex42")
        @test r.exitcode == 0
    end

    @testset "ex42 6: bddc_stokes_deluxe" begin
        args = `-mx 5 -my 4 -mz 3 -stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type bddc -dm_mat_type is -stokes_pc_bddc_dirichlet_pc_type svd -stokes_pc_bddc_neumann_pc_type svd -stokes_pc_bddc_coarse_redundant_pc_type svd -stokes_pc_bddc_use_deluxe_scaling -stokes_sub_schurs_posdef 0 -stokes_sub_schurs_symmetric -stokes_sub_schurs_mat_solver_type petsc`
        r = run_petsc_ex(args, 6, "ex42")
        @test r.exitcode == 0
    end

    @testset "ex42 9: bddc_stokes_subdomainjump_deluxe" begin
        args = `-model 4 -jump_magnitude 4 -mx 6 -my 6 -mz 2 -stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type bddc -dm_mat_type is -stokes_pc_bddc_use_deluxe_scaling -stokes_sub_schurs_posdef 0 -stokes_sub_schurs_symmetric -stokes_sub_schurs_mat_solver_type petsc -stokes_pc_bddc_schur_layers 1`
        r = run_petsc_ex(args, 9, "ex42")
        @test r.exitcode == 0
    end

    @testset "ex42 1: fieldsplit" begin
        args = `-stokes_ksp_converged_reason -stokes_pc_type fieldsplit -resolve`
        r = run_petsc_ex(args, 1, "ex42")
        @test r.exitcode == 0
    end

    @testset "ex42 4: tut" begin
        args = `-stokes_ksp_monitor`
        r = run_petsc_ex(args, 4, "ex42")
        @test r.exitcode == 0
    end

    @testset "ex42 4: tut_2" begin
        args = ` -stokes_ksp_monitor -stokes_pc_type fieldsplit -stokes_pc_fieldsplit_type schur`
        r = run_petsc_ex(args, 4, "ex42")
        @test r.exitcode == 0
    end

    @testset "ex42 4: tut_3" begin
        args = ` -mx 20 -stokes_ksp_monitor -stokes_pc_type fieldsplit -stokes_pc_fieldsplit_type schur`
        r = run_petsc_ex(args, 4, "ex42")
        @test r.exitcode == 0
    end

    @testset "ex4  1: direct_umfpack suitesparse" begin
        if test_suitesparse
            args = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 12 -stag_grid_y 7 -pc_type lu -pc_factor_mat_solver_type umfpack -ksp_converged_reason`;
            r = run_petsc_ex(args, 1, "ex4")

            @test r.exitcode == 0
        end
    end
    
    @testset "ex4  4: direct mumps" begin
        if test_mumps
            args  = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 13 -stag_grid_y 8 -pc_type lu -pc_factor_mat_solver_type mumps -ksp_converged_reason`;
            cores = 4
            r = run_petsc_ex(args, cores, "ex4")
            @test r.exitcode == 0
        end
    end

    
    @testset "ex4  4: direct superlu_dist" begin
        if test_superlu_dist
            args  = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 13 -stag_grid_y 8 -pc_type lu -pc_factor_mat_solver_type superlu_dist -ksp_converged_reason`;
            cores = 4
            r = run_petsc_ex(args, cores, "ex4")

            @test r.exitcode == 0
        end
    end
    
    @testset "ex4  1: isovisc_nondim_abf_mg" begin
        args = `-dim 2 -coefficients layers -nondimensional 1 -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -fieldsplit_face_pc_type mg -fieldsplit_face_pc_mg_levels 3 -stag_grid_x 24 -stag_grid_y 24 -fieldsplit_face_pc_mg_galerkin -fieldsplit_face_ksp_converged_reason -ksp_type fgmres -fieldsplit_element_pc_type none -fieldsplit_face_mg_levels_ksp_max_it 6 -pc_fieldsplit_schur_fact_type upper -isoviscous `;
        r = run_petsc_ex(args, 1, "ex4")
        @test r.exitcode == 0
    end

    @testset "ex4  1: isovisc_nondim_abf_mg_2" begin
        args = `-dim 2 -coefficients layers -nondimensional -isoviscous -eta1 1.0 -stag_grid_x 32 -stag_grid_y 32 -ksp_type fgmres -pc_type fieldsplit -pc_fieldsplit_type schur -pc_fieldsplit_schur_fact_type upper -build_auxiliary_operator -fieldsplit_element_ksp_type preonly -fieldsplit_element_pc_type jacobi -fieldsplit_face_pc_type mg -fieldsplit_face_pc_mg_levels 3 -fieldsplit_face_pc_mg_galerkin -fieldsplit_face_mg_levels_pc_type jacobi -fieldsplit_face_mg_levels_ksp_type chebyshev -ksp_converged_reason `;
        r = run_petsc_ex(args, 1, "ex4")
        
        @test r.exitcode == 0
    end

    @testset "ex4  1: nondim_abf_lu suitesparse" begin
        if test_suitesparse
            args = `-dim 2 -coefficients layers -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -ksp_type fgmres -fieldsplit_element_pc_type none -pc_fieldsplit_schur_fact_type upper -nondimensional -eta1 1e-2 -eta2 1.0 -isoviscous 0 -ksp_monitor -fieldsplit_element_pc_type jacobi -build_auxiliary_operator -fieldsplit_face_pc_type lu -fieldsplit_face_pc_factor_mat_solver_type umfpack -stag_grid_x 32 -stag_grid_y 32        `;
            r = run_petsc_ex(args, 1, "ex4")
            @test r.exitcode == 0
        end
    end

    @testset "ex4  2: nondim_abf_lu mumps" begin
        if test_mumps
            args = `-dim 2 -coefficients layers -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -ksp_type fgmres -fieldsplit_element_pc_type none -pc_fieldsplit_schur_fact_type upper -nondimensional -eta1 1e-2 -eta2 1.0 -isoviscous 0 -ksp_monitor -fieldsplit_element_pc_type jacobi -build_auxiliary_operator -fieldsplit_face_pc_type lu -fieldsplit_face_pc_factor_mat_solver_type mumps -stag_grid_x 32 -stag_grid_y 32        `;
            r = run_petsc_ex(args, 2, "ex4")
            @test r.exitcode == 0
        end
    end

    @testset "ex4  1: 3d_nondim_isovisc_abf_mg" begin
        
        args = `-dim 3 -coefficients layers -isoviscous -nondimensional -build_auxiliary_operator -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -fieldsplit_face_pc_type mg -fieldsplit_face_pc_mg_levels 3 -s 16 -fieldsplit_face_pc_mg_galerkin -fieldsplit_face_ksp_converged_reason -ksp_type fgmres -fieldsplit_element_pc_type none -fieldsplit_face_mg_levels_ksp_max_it 6 -pc_fieldsplit_schur_fact_type upper`;
        r = run_petsc_ex(args, 1, "ex4")
        @test r.exitcode == 0
    end

    @testset "ex4  1: monolithic 2D" begin
        args = `-dim 2 -s 16 -custom_pc_mat -pc_type mg -pc_mg_levels 3 -pc_mg_galerkin -mg_levels_ksp_type gmres -mg_levels_ksp_norm_type unpreconditioned -mg_levels_ksp_max_it 10 -mg_levels_pc_type jacobi -ksp_converged_reason     `;
        r = run_petsc_ex(args, 1, "ex4")
        @test r.exitcode == 0
    end

    @testset "ex4  1: monolithic 3D" begin
        args = `-dim 3 -s 16 -custom_pc_mat -pc_type mg -pc_mg_levels 3 -pc_mg_galerkin -mg_levels_ksp_type gmres -mg_levels_ksp_norm_type unpreconditioned -mg_levels_ksp_max_it 10 -mg_levels_pc_type jacobi -ksp_converged_reason     `;
        r = run_petsc_ex(args, 1, "ex4")
        @test r.exitcode == 0
    end

    @testset "ex4  1: 3d_nondim_isovisc_sinker_abf_mg" begin
        args = `-dim 3 -coefficients sinker -isoviscous -nondimensional -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -fieldsplit_face_pc_type mg -fieldsplit_face_pc_mg_levels 3 -s 16 -fieldsplit_face_pc_mg_galerkin -fieldsplit_face_ksp_converged_reason -ksp_type fgmres -fieldsplit_element_pc_type none -fieldsplit_face_mg_levels_ksp_max_it 6 -pc_fieldsplit_schur_fact_type upper        `;
        r = run_petsc_ex(args, 1, "ex4")
        @test r.exitcode == 0
    end

    
    @testset "ex4  1: 3d_nondim_mono_mg_lamemstyle suitesparse" begin
        if test_suitesparse
            args = `-dim 3 -coefficients layers -nondimensional -s 16 -custom_pc_mat -pc_type mg -pc_mg_galerkin -pc_mg_levels 2 -mg_levels_ksp_type richardson -mg_levels_pc_type jacobi -mg_levels_ksp_richardson_scale 0.5 -mg_levels_ksp_max_it 20 -mg_coarse_pc_type lu -mg_coarse_pc_factor_mat_solver_type umfpack -ksp_converged_reason        `;
            r = run_petsc_ex(args, 1, "ex4")
            @test r.exitcode == 0
        end
    end
    
    @testset "ex4  1: 3d_nondim_mono_mg_lamemstyle mumps" begin
        if test_mumps
            args = ` -dim 3 -coefficients layers -nondimensional -s 16 -custom_pc_mat -pc_type mg -pc_mg_galerkin -pc_mg_levels 2 -mg_levels_ksp_type richardson -mg_levels_pc_type jacobi -mg_levels_ksp_richardson_scale 0.5 -mg_levels_ksp_max_it 20 -mg_coarse_pc_type lu -mg_coarse_pc_factor_mat_solver_type mumps -ksp_converged_reason        `;
            r = run_petsc_ex(args, 1, "ex4")
            @test r.exitcode == 0
        end
    end

    
    @testset "ex4  2: 3d_nondim_mono_mg_lamemstyle superlu_dist" begin
        if test_superlu_dist
            args = `-dim 3 -coefficients layers -nondimensional -s 16 -custom_pc_mat -pc_type mg -pc_mg_galerkin -pc_mg_levels 2 -mg_levels_ksp_type richardson -mg_levels_pc_type jacobi -mg_levels_ksp_richardson_scale 0.5 -mg_levels_ksp_max_it 20 -mg_coarse_pc_type lu -mg_coarse_pc_factor_mat_solver_type superlu_dist -ksp_converged_reason        `;
            r = run_petsc_ex(args, 2, "ex4")

            @test r.exitcode == 0
        end
    end
    

end

