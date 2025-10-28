using Test, Pkg, Base.Sys

# BLAS library used here:
using CompilerSupportLibraries_jll, MPIPreferences
            
export mpirun, deactivate_multithreading, run_petsc_ex

# ensure that we use the correct version of the package 
Pkg.add(url="https://github.com/boriskaus/PETSc_jll.jl")
#Pkg.add("PETSc_jll")
using PETSc_jll

Pkg.add("OpenBLAS32")
using OpenBLAS32



# Show the host platform (debug info)
@show Base.BinaryPlatforms.HostPlatform()
@show  PETSc_jll.host_platform
@show  names(PETSc_jll)

#setup MPI
if isdefined(PETSc_jll,:MPICH_jll)
    const mpiexec = PETSc_jll.MPICH_jll.mpiexec()
    const MPI_LIBPATH = PETSc_jll.MPICH_jll.LIBPATH
elseif isdefined(PETSc_jll,:MicrosoftMPI_jll) 
    const mpiexec = PETSc_jll.MicrosoftMPI_jll.mpiexec()
    const MPI_LIBPATH = PETSc_jll.MicrosoftMPI_jll.LIBPATH
elseif isdefined(PETSc_jll,:OpenMPI_jll) 
    const mpiexec = PETSc_jll.OpenMPI_jll.mpiexec()
    const MPI_LIBPATH = PETSc_jll.OpenMPI_jll.LIBPATH
elseif isdefined(PETSc_jll,:MPItrampoline_jll) 
    const mpiexec = PETSc_jll.MPItrampoline_jll.mpiexec()
    const MPI_LIBPATH = PETSc_jll.MPItrampoline_jll.LIBPATH
else
    println("Be careful! No MPI library detected; parallel runs won't work")
    const mpiexec = nothing
    const MPI_LIBPATH = Ref{String}("")
end

@show mpiexec



function deactivate_multithreading(cmd::Cmd)
    # multithreading of the BLAS libraries that is installed by default with the julia BLAS
    # does not work well. Switch that off:
    cmd = addenv(cmd,"OMP_NUM_THREADS"=>1)
    cmd = addenv(cmd,"VECLIB_MAXIMUM_THREADS"=>1)

    return cmd
end

# Shamelessly stolen from the tests of LBT 
if Sys.iswindows()
    LIBPATH_env = "PATH"
    LIBPATH_default = ""
    pathsep = ';'
    binlib = "bin"
    shlib_ext = "dll"
elseif Sys.isapple()
    LIBPATH_env = "DYLD_FALLBACK_LIBRARY_PATH"
    LIBPATH_default = "~/lib:/usr/local/lib:/lib:/usr/lib"
    pathsep = ':'
    binlib = "lib"
    shlib_ext = "dylib"
else
    LIBPATH_env = "LD_LIBRARY_PATH"
    LIBPATH_default = ""
    pathsep = ':'
    binlib = "lib"
    shlib_ext = "so"
end

if !isnothing(mpiexec)
    key = PETSc_jll.JLLWrappers.JLLWrappers.LIBPATH_env
    mpirun = addenv(mpiexec, key=>join((PETSc_jll.LIBPATH[], MPI_LIBPATH[]), pathsep));

#    mpirun = setenv(mpiexec, PETSc_jll.JLLWrappers.JLLWrappers.LIBPATH_env=>PETSc_jll.LIBPATH[]);
else
    mpirun = nothing;
end

function append_libpath(paths::Vector{<:AbstractString}, ENV::Vector{<:AbstractString})
    
    return join(vcat(paths..., ENV[first(findall(contains.(ENV,"$LIBPATH_env")))]), pathsep)
end


function add_LBT_flags(cmd::Cmd)
    # using LBT requires to set the following environment variables
    #libdirs = unique(vcat(OpenBLAS32_jll.LIBPATH_list..., CompilerSupportLibraries_jll.LIBPATH_list...))
    libdirs = unique(vcat(CompilerSupportLibraries_jll.LIBPATH_list...))
    
    #backing_libs = OpenBLAS32_jll.libopenblas_path
    
    env = Dict(
        # We need to tell it how to find CSL at run-time
        LIBPATH_env => append_libpath(libdirs, cmd.env),
        #"LBT_DEFAULT_LIBS" => backing_libs,
        #"LBT_STRICT" => 1,
        #"LBT_VERBOSE" => 0,
    )

    if !Sys.iswindows()
        # adding the environmental variables on windows seems to cause a crash
        cmd = addenv(cmd, env)
    end
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
            #cmd = `$(PETSc_jll.ex4_int64_deb())  $args`
        elseif ex=="ex42"
            cmd = `$(PETSc_jll.ex42())  $args`
        elseif ex=="ex19"
            cmd = `$(PETSc_jll.ex19_int64_deb())  $args`
            #cmd = `$(PETSc_jll.ex19())  $args`
        elseif ex=="ex19_32"
            cmd = `$(PETSc_jll.ex19_int32())  $args`
            #cmd = `$(PETSc_jll.ex19())  $args`
        else
            error("unknown example")
        end
        if deactivate_multithreads
            cmd = deactivate_multithreading(cmd)
        end
        
        # add stuff related to LBT on systems that support it
        cmd = add_LBT_flags(cmd)
        
        r = run(cmd, wait=wait);
    else
        # create command-line object
        if ex=="ex4"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex4_path) $args`
            #cmd = `$(mpirun) -n $cores $(PETSc_jll.ex4_int64_deb_path) $args`
        elseif ex=="ex42"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex42_path) $args`
        elseif ex=="ex19"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex19_int64_deb_path) $args`
            #cmd = `$(mpirun) -n $cores $(PETSc_jll.ex19_path) $args`
        elseif ex=="ex19_32"
            cmd = `$(PETSc_jll.ex19_int32())  $args`
            #cmd = `$(PETSc_jll.ex19())  $args`            
        else
            error("unknown example")
        end
        if deactivate_multithreads
            cmd = deactivate_multithreading(cmd)
        end

        # add stuff related to LBT
        cmd = add_LBT_flags(cmd)

        # Run example in parallel
        r = run(cmd, wait=wait);
    end

    return r
end


test_suitesparse = true
test_superlu_dist = true
test_mumps = true

if iswindows()
    is_parallel = false;        # activate parallel tests
    mpi_single_core = false;    # performs a single-core run without calling MPI
    test_suitesparse = false
    test_superlu_dist = false
    test_mumps = false
else
    is_parallel = true;         # activate parallel tests
    mpi_single_core = true;     
end
@testset verbose = true "ex19, ex42, ex4" begin

    #@testset "test_MWE" begin
    #    include("test_MWE.jl")
    #end
    
    
    if any(names(PETSc_jll) .== :ex19)

        for ex19_case in ["ex19", "ex19_32"]

            # Note: ex19 is the default test that PETSc performs @ the end of the installation process
            @testset "$ex19_case 1: iterative" begin
                args = `-da_refine 3 -pc_type mg -ksp_type fgmres`;
                r = run_petsc_ex(args, 1, ex19_case, mpi_single_core=mpi_single_core)
                @test r.exitcode == 0
            end
            
            # testex19_mpi:
            @testset "$ex19_case 2: mpi" begin
                if is_parallel
                    args = `-da_refine 3 -pc_type mg -ksp_type fgmres`;
                    r = run_petsc_ex(args, 2, ex19_case)
                    @test r.exitcode == 0
                end
            end

            # runex19_fieldsplit_mumps
            @testset "$ex19_case 2: fieldsplit_mumps" begin
                if test_mumps & is_parallel
                    args = `-pc_type fieldsplit -pc_fieldsplit_block_size 4 -pc_fieldsplit_type SCHUR -pc_fieldsplit_0_fields 0,1,2 -pc_fieldsplit_1_fields 3 -fieldsplit_0_pc_type lu -fieldsplit_1_pc_type lu -snes_monitor_short -ksp_monitor_short  -fieldsplit_0_pc_factor_mat_solver_type mumps -fieldsplit_1_pc_factor_mat_solver_type mumps`;
                    r = run_petsc_ex(args, 2, ex19_case)
                    @test r.exitcode == 0
                end
            end

            # runex19_superlu_dist
            @testset "$ex19_case 2: fieldsplit_superlu_dist" begin
                if test_superlu_dist & is_parallel
                    #args = `-da_grid_x 20 -da_grid_y 20 -pc_type lu -pc_factor_mat_solver_type superlu_dist`;
                    args = `-pc_type fieldsplit -pc_fieldsplit_block_size 4 -pc_fieldsplit_type SCHUR -pc_fieldsplit_0_fields 0,1,2 -pc_fieldsplit_1_fields 3 -fieldsplit_0_pc_type lu -fieldsplit_1_pc_type lu -snes_monitor_short -ksp_monitor_short  -fieldsplit_0_pc_factor_mat_solver_type superlu_dist -fieldsplit_1_pc_factor_mat_solver_type superlu_dist`;
                    
                    r = run_petsc_ex(args, 2, ex19_case)
                    @test r.exitcode == 0
                end
            end
            
            # runex19_suitesparse
            @testset "$ex19_case 1: suitesparse" begin
                if test_suitesparse
                    args = `-da_refine 3 -snes_monitor_short -pc_type lu -pc_factor_mat_solver_type umfpack`;
                    r = run_petsc_ex(args, 1, "ex19", mpi_single_core=mpi_single_core)
                    @test r.exitcode == 0
                end
            end
        end
        
    end

    
    @testset "ex42 1: serial" begin
        args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type lu`;
        r = run_petsc_ex(args, 1, "ex42", mpi_single_core=mpi_single_core)
        @test r.exitcode == 0
    end
    
    @testset "ex42 2: mumps" begin
        if test_mumps & is_parallel
            args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type lu -stokes_pc_factor_mat_solver_type mumps `;
            r = run_petsc_ex(args, 2, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex42 2: superlu_dist" begin
        if test_superlu_dist & is_parallel
            args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type lu -stokes_pc_factor_mat_solver_type superlu_dist `;
            r = run_petsc_ex(args, 2, "ex42")
            @test r.exitcode == 0
        end
    end
    
    @testset "ex42 3: redundant lu" begin
        if  is_parallel
            args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type redundant -stokes_redundant_pc_type lu`;
            r = run_petsc_ex(args, 3, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex42 6: bddc_stokes" begin
        if is_parallel
            args = `-mx 5 -my 4 -mz 3 -stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type bddc -dm_mat_type is -stokes_pc_bddc_dirichlet_pc_type svd -stokes_pc_bddc_neumann_pc_type svd -stokes_pc_bddc_coarse_redundant_pc_type svd`;
            r = run_petsc_ex(args, 6, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex42 6: bddc_stokes_deluxe" begin
        if is_parallel 
            args = `-mx 5 -my 4 -mz 3 -stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type bddc -dm_mat_type is -stokes_pc_bddc_dirichlet_pc_type svd -stokes_pc_bddc_neumann_pc_type svd -stokes_pc_bddc_coarse_redundant_pc_type svd -stokes_pc_bddc_use_deluxe_scaling -stokes_sub_schurs_posdef 0 -stokes_sub_schurs_symmetric -stokes_sub_schurs_mat_solver_type petsc`
            r = run_petsc_ex(args, 6, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex42 9: bddc_stokes_subdomainjump_deluxe" begin
        if is_parallel 
            args = `-model 4 -jump_magnitude 4 -mx 6 -my 6 -mz 2 -stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type bddc -dm_mat_type is -stokes_pc_bddc_use_deluxe_scaling -stokes_sub_schurs_posdef 0 -stokes_sub_schurs_symmetric -stokes_sub_schurs_mat_solver_type petsc -stokes_pc_bddc_schur_layers 1`
            r = run_petsc_ex(args, 9, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex42 1: fieldsplit" begin
        args = `-stokes_ksp_converged_reason -stokes_pc_type fieldsplit -resolve`
        r = run_petsc_ex(args, 1, "ex42", mpi_single_core=mpi_single_core)
        @test r.exitcode == 0
    end

    @testset "ex42 4: tut" begin
        if is_parallel 
            args = `-stokes_ksp_monitor`
            r = run_petsc_ex(args, 4, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex42 4: tut_2" begin
        if is_parallel 
            args = ` -stokes_ksp_monitor -stokes_pc_type fieldsplit -stokes_pc_fieldsplit_type schur`
            r = run_petsc_ex(args, 4, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex42 4: tut_3" begin
        if  is_parallel 
            args = ` -mx 20 -stokes_ksp_monitor -stokes_pc_type fieldsplit -stokes_pc_fieldsplit_type schur`
            r = run_petsc_ex(args, 4, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex4  1: direct_umfpack suitesparse" begin
        if test_suitesparse
            args = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 12 -stag_grid_y 7 -pc_type lu -pc_factor_mat_solver_type umfpack -ksp_converged_reason`;
            r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)

            @test r.exitcode == 0
        end
    end
    
    @testset "ex4  4: direct mumps" begin
        if test_mumps & is_parallel
            args  = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 13 -stag_grid_y 8 -pc_type lu -pc_factor_mat_solver_type mumps -ksp_converged_reason`;
            cores = 4
            r = run_petsc_ex(args, cores, "ex4")
            @test r.exitcode == 0
        end
    end

    @testset "ex4  4: direct superlu_dist" begin
        if test_superlu_dist & is_parallel
            args  = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 13 -stag_grid_y 8 -pc_type lu -pc_factor_mat_solver_type superlu_dist -ksp_converged_reason`;
            cores = 4
            r = run_petsc_ex(args, cores, "ex4")

            @test r.exitcode == 0
        end
    end
    
    @testset "ex4  1: isovisc_nondim_abf_mg" begin
        args = `-dim 2 -coefficients layers -nondimensional 1 -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -fieldsplit_face_pc_type mg -fieldsplit_face_pc_mg_levels 3 -stag_grid_x 24 -stag_grid_y 24 -fieldsplit_face_pc_mg_galerkin -fieldsplit_face_ksp_converged_reason -ksp_type fgmres -fieldsplit_element_pc_type none -fieldsplit_face_mg_levels_ksp_max_it 6 -pc_fieldsplit_schur_fact_type upper -isoviscous `;
        r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
        @test r.exitcode == 0
    end

    @testset "ex4  1: isovisc_nondim_abf_mg_2" begin
        args = `-dim 2 -coefficients layers -nondimensional -isoviscous -eta1 1.0 -stag_grid_x 32 -stag_grid_y 32 -ksp_type fgmres -pc_type fieldsplit -pc_fieldsplit_type schur -pc_fieldsplit_schur_fact_type upper -build_auxiliary_operator -fieldsplit_element_ksp_type preonly -fieldsplit_element_pc_type jacobi -fieldsplit_face_pc_type mg -fieldsplit_face_pc_mg_levels 3 -fieldsplit_face_pc_mg_galerkin -fieldsplit_face_mg_levels_pc_type jacobi -fieldsplit_face_mg_levels_ksp_type chebyshev -ksp_converged_reason `;
        r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
        
        @test r.exitcode == 0
    end

    @testset "ex4  1: nondim_abf_lu suitesparse" begin
        if test_suitesparse
            args = `-dim 2 -coefficients layers -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -ksp_type fgmres -fieldsplit_element_pc_type none -pc_fieldsplit_schur_fact_type upper -nondimensional -eta1 1e-2 -eta2 1.0 -isoviscous 0 -ksp_monitor -fieldsplit_element_pc_type jacobi -build_auxiliary_operator -fieldsplit_face_pc_type lu -fieldsplit_face_pc_factor_mat_solver_type umfpack -stag_grid_x 32 -stag_grid_y 32        `;
            r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
            @test r.exitcode == 0
        end
    end

    @testset "ex4  2: nondim_abf_lu mumps" begin
        if test_mumps & is_parallel
            args = `-dim 2 -coefficients layers -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -ksp_type fgmres -fieldsplit_element_pc_type none -pc_fieldsplit_schur_fact_type upper -nondimensional -eta1 1e-2 -eta2 1.0 -isoviscous 0 -ksp_monitor -fieldsplit_element_pc_type jacobi -build_auxiliary_operator -fieldsplit_face_pc_type lu -fieldsplit_face_pc_factor_mat_solver_type mumps -stag_grid_x 32 -stag_grid_y 32        `;
            r = run_petsc_ex(args, 2, "ex4")
            @test r.exitcode == 0
        end
    end

    @testset "ex4  1: 3d_nondim_isovisc_abf_mg" begin
        args = `-dim 3 -coefficients layers -isoviscous -nondimensional -build_auxiliary_operator -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -fieldsplit_face_pc_type mg -fieldsplit_face_pc_mg_levels 3 -s 16 -fieldsplit_face_pc_mg_galerkin -fieldsplit_face_ksp_converged_reason -ksp_type fgmres -fieldsplit_element_pc_type none -fieldsplit_face_mg_levels_ksp_max_it 6 -pc_fieldsplit_schur_fact_type upper`;
        r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
        @test r.exitcode == 0
    end

    @testset "ex4  1: monolithic 2D" begin
        args = `-dim 2 -s 16 -custom_pc_mat -pc_type mg -pc_mg_levels 3 -pc_mg_galerkin -mg_levels_ksp_type gmres -mg_levels_ksp_norm_type unpreconditioned -mg_levels_ksp_max_it 10 -mg_levels_pc_type jacobi -ksp_converged_reason     `;
        r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
        @test r.exitcode == 0
    end

    @testset "ex4  1: monolithic 3D" begin
        args = `-dim 3 -s 16 -custom_pc_mat -pc_type mg -pc_mg_levels 3 -pc_mg_galerkin -mg_levels_ksp_type gmres -mg_levels_ksp_norm_type unpreconditioned -mg_levels_ksp_max_it 10 -mg_levels_pc_type jacobi -ksp_converged_reason     `;
        r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
        @test r.exitcode == 0
    end

    @testset "ex4  1: 3d_nondim_isovisc_sinker_abf_mg" begin
        args = `-dim 3 -coefficients sinker -isoviscous -nondimensional -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -fieldsplit_face_pc_type mg -fieldsplit_face_pc_mg_levels 3 -s 16 -fieldsplit_face_pc_mg_galerkin -fieldsplit_face_ksp_converged_reason -ksp_type fgmres -fieldsplit_element_pc_type none -fieldsplit_face_mg_levels_ksp_max_it 6 -pc_fieldsplit_schur_fact_type upper        `;
        r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
        @test r.exitcode == 0
    end

    
    @testset "ex4  1: 3d_nondim_mono_mg_lamemstyle suitesparse" begin
        if test_suitesparse
            args = `-dim 3 -coefficients layers -nondimensional -s 16 -custom_pc_mat -pc_type mg -pc_mg_galerkin -pc_mg_levels 2 -mg_levels_ksp_type richardson -mg_levels_pc_type jacobi -mg_levels_ksp_richardson_scale 0.5 -mg_levels_ksp_max_it 20 -mg_coarse_pc_type lu -mg_coarse_pc_factor_mat_solver_type umfpack -ksp_converged_reason        `;
            r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
            @test r.exitcode == 0
        end
    end
    
    @testset "ex4  1: 3d_nondim_mono_mg_lamemstyle mumps" begin
        if test_mumps
            args = ` -dim 3 -coefficients layers -nondimensional -s 16 -custom_pc_mat -pc_type mg -pc_mg_galerkin -pc_mg_levels 2 -mg_levels_ksp_type richardson -mg_levels_pc_type jacobi -mg_levels_ksp_richardson_scale 0.5 -mg_levels_ksp_max_it 20 -mg_coarse_pc_type lu -mg_coarse_pc_factor_mat_solver_type mumps -ksp_converged_reason        `;
            r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
            @test r.exitcode == 0
        end
    end

    
    @testset "ex4  2: 3d_nondim_mono_mg_lamemstyle superlu_dist" begin
        if test_superlu_dist & is_parallel
            args = `-dim 3 -coefficients layers -nondimensional -s 16 -custom_pc_mat -pc_type mg -pc_mg_galerkin -pc_mg_levels 2 -mg_levels_ksp_type richardson -mg_levels_pc_type jacobi -mg_levels_ksp_richardson_scale 0.5 -mg_levels_ksp_max_it 20 -mg_coarse_pc_type lu -mg_coarse_pc_factor_mat_solver_type superlu_dist -ksp_converged_reason        `;
            r = run_petsc_ex(args, 2, "ex4")

            @test r.exitcode == 0
        end
    end
    
end

