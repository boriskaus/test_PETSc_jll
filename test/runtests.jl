using Test, Pkg, Base.Sys

# BLAS library used here:
using CompilerSupportLibraries_jll, MPIPreferences, OpenBLAS32_jll
            
export mpirun, deactivate_multithreading, run_petsc_ex

# ensure that we use the correct version of the package.
#
# By default the PETSc_jll that was deployed to GitHub is used (this is what CI
# tests).  To test a PETSc_jll that was built locally with BinaryBuilder
# (`julia build_tarballs.jl --deploy=local <triplet>`), point the environment
# variable PETSC_JLL_LOCAL_PATH to the generated JLL directory, e.g.
#   PETSC_JLL_LOCAL_PATH=<jll dir> julia --project=. -e 'using Pkg; Pkg.develop(path=ENV["PETSC_JLL_LOCAL_PATH"]); Pkg.test()'
if haskey(ENV, "MUMPS_JLL_LOCAL_PATH")
    local_mumps = expanduser(ENV["MUMPS_JLL_LOCAL_PATH"])
    println("Using locally built MUMPS_jll from $local_mumps")
    Pkg.develop(path=local_mumps)
end
if haskey(ENV, "PETSC_JLL_LOCAL_PATH")
    local_jll = expanduser(ENV["PETSC_JLL_LOCAL_PATH"])
    println("Using locally built PETSc_jll from $local_jll")
    Pkg.develop(path=local_jll)
else
    #Pkg.add(url="https://github.com/boriskaus/PETSc_jll.jl")
    Pkg.add(url="https://github.com/boriskaus/PETSc_jll1.jl")
end
using PETSc_jll

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
    # ENV entries are raw "KEY=VALUE" strings; strip the "LIBPATH_env=" prefix
    # so we don't embed a literal "LD_LIBRARY_PATH=..." inside the new value.
    idx = findfirst(startswith("$LIBPATH_env="), ENV)
    existing = idx === nothing ? LIBPATH_default : split(ENV[idx], '='; limit=2)[2]

    return join(vcat(paths..., existing), pathsep)
end


function add_LBT_flags(cmd::Cmd)
    # PETSc itself calls BLAS through libblastrampoline (LBT) using the
    # ILP64 (`_64_`) symbols, while MUMPS_jll/SuperLU_DIST_jll (linked in as
    # separate shared libraries) make their own internal, plain LP64 BLAS
    # calls (dgemm_, idamax_, ...) also routed through LBT. Neither slot has
    # a backing library registered by default in a bare subprocess (unlike
    # inside a Julia process, where the stdlib OpenBLAS/OpenBLAS32_jll
    # auto-register), so unregistered calls either segfault (ILP64, e.g.
    # BLASdot()/VecNorm_Seq) or hard-error with "no BLAS/LAPACK library
    # loaded" (LP64, inside MUMPS/SuperLU_DIST). Point LBT_DEFAULT_LIBS at
    # both Julia's bundled ILP64 OpenBLAS (libopenblas64_) and
    # OpenBLAS32_jll's LP64 library; LBT auto-detects each one's word size.
    # See https://github.com/JuliaPackaging/Yggdrasil/pull/13691 and #13696.
    libdirs = unique(vcat(CompilerSupportLibraries_jll.LIBPATH_list...))

    # Julia's own ILP64 OpenBLAS: lib/julia/ on Linux and macOS, next to julia.exe on Windows.
    ilp64_lib = Sys.iswindows() ? joinpath(Sys.BINDIR, "libopenblas64_.dll") :
                                  joinpath(Sys.BINDIR, "..", "lib", "julia", "libopenblas64_.$shlib_ext")
    lp64_lib = OpenBLAS32_jll.libopenblas_path
    backing_libs = join((ilp64_lib, lp64_lib), ";")

    env = Dict(
        # We need to tell it how to find CSL at run-time
        LIBPATH_env => append_libpath(libdirs, cmd.env),
        "LBT_DEFAULT_LIBS" => backing_libs,
    )

    if Sys.iswindows()
        # On Windows PETSc_jll links OpenBLAS_jll's libopenblas64_.dll directly, but Julia's
        # SuiteSparse_jll (umfpack/cholmod call dgemv_64_ ...) and MUMPS_jll/SCALAPACK32_jll
        # (LP64) go through libblastrampoline-5.dll, so both slots need a backing library
        # here as well.  PATH is left alone: mpirun already carries PETSc_jll.LIBPATH, which
        # holds every dependency's bin directory, CompilerSupportLibraries included; adding
        # the variables here used to crash the child processes on Windows.
        cmd = addenv(cmd, "LBT_DEFAULT_LIBS" => backing_libs)
    else
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
        cmd = add_LBT_flags(cmd)

        r = run(cmd, wait=wait);
    else
        # create command-line object
        # (use .exec[1] to get a plain executable path: interpolating two
        # env-carrying Cmds, e.g. mpirun and PETSc_jll.ex19_int64_deb(), in
        # the same backtick literal is rejected by Julia's Cmd construction)
        if ex=="ex4"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex4().exec[1]) $args`
        elseif ex=="ex42"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex42().exec[1]) $args`
        elseif ex=="ex19"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex19_int64_deb().exec[1]) $args`
        elseif ex=="ex19_32"
            cmd = `$(mpirun) -n $cores $(PETSc_jll.ex19_int32().exec[1]) $args`
        else
            error("unknown example")
        end
        if deactivate_multithreads
            cmd = deactivate_multithreading(cmd)
        end
        cmd = add_LBT_flags(cmd)

        # Run example in parallel
        r = run(cmd, wait=wait);
    end

    return r
end


test_suitesparse = true
test_superlu_dist = true
test_mumps = true

# SuperLU_DIST in the Int64 PetscInt variants (ex4/ex42 and the default ex19
# executable are Int64 builds).  This needs PETSc_jll >= 3.25.4 built against
# MUMPS_jll's `_metis64` flavour: SuperLU_DIST_jll's Int64 library uses the
# 64-bit-index METIS/ParMETIS, which exports the same symbol names as the
# 32-bit METIS the stock MUMPS libraries link, and the two cannot coexist in
# one process (see https://github.com/JuliaPackaging/Yggdrasil/pull/13691).
# Set to false to test a PETSc_jll whose Int64 variants have no SuperLU_DIST.
test_superlu_dist_int64 = true

if iswindows()
    # PETSc_jll >= 3.25.4 is built with MS-MPI on Windows again (the load-time pseudo-relocation
    # abort came from PETSc's Fortran bindings, which are now disabled there), so the parallel
    # runs are on, and so are the external packages: MUMPS (MUMPS_jll's MS-MPI build, stock
    # flavour), SuperLU_DIST (SuperLU_DIST_jll, built without METIS/ParMETIS on Windows), hypre
    # and SuiteSparse.
    is_parallel = true;         # activate parallel tests (mpiexec from MicrosoftMPI_jll)
    mpi_single_core = true;     # performs a single-core run without calling MPI
    test_suitesparse = true
    test_superlu_dist = true
    test_mumps = true
else
    is_parallel = true;         # activate parallel tests
    mpi_single_core = true;     
end
# HDF5 output through PETSc's viewer.  PETSc_jll is only built with HDF5 once HDF5_jll
# provides a parallel build on every platform (Yggdrasil #14782), so detect it at run time:
# without HDF5 the viewer spec `hdf5:...` makes PETSc stop with
# "Unknown PetscViewer type given: hdf5".
const HDF5_SIGNATURE = UInt8[0x89, 0x48, 0x44, 0x46, 0x0d, 0x0a, 0x1a, 0x0a]

is_hdf5_file(fname) = isfile(fname) && open(io -> read(io, 8), fname) == HDF5_SIGNATURE

function petsc_has_hdf5()
    dir = mktempdir()
    try
        cd(dir) do
            r = run_petsc_ex(`-da_refine 1 -snes_view_solution hdf5:sol.h5`, 1, "ex19",
                             mpi_single_core=mpi_single_core)
            return r.exitcode == 0 && is_hdf5_file("sol.h5")
        end
    catch
        return false
    end
end

test_hdf5 = petsc_has_hdf5()
@show test_hdf5

# GPU (CUDA) tests.  `-use_gpu_aware_mpi 0` because the MPI JLLs are not built CUDA-aware.  They need three things: a PETSc_jll built with CUDA (PETSc_GPU_jll),
# an NVIDIA driver, and a device.  Without a device PETSc stops with "unable to initialize
# CUDA"/"CUDA error", so probe once and skip the testsets when there is nothing to run on.
function petsc_has_cuda()
    dir = mktempdir()
    try
        cd(dir) do
            r = run_petsc_ex(`-da_refine 1 -dm_vec_type cuda -dm_mat_type aijcusparse -use_gpu_aware_mpi 0 -ksp_type cg -pc_type jacobi`,
                             1, "ex19", mpi_single_core=mpi_single_core)
            return r.exitcode == 0
        end
    catch
        return false
    end
end

has_nvidia_gpu = Sys.islinux() && !isnothing(Sys.which("nvidia-smi")) &&
                 success(pipeline(`nvidia-smi -L`, devnull))
test_cuda = has_nvidia_gpu && petsc_has_cuda()
@show has_nvidia_gpu test_cuda


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
                if test_superlu_dist & is_parallel & (ex19_case == "ex19_32" || test_superlu_dist_int64)
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

            # Regression tests for the METIS integer-width clash: force MUMPS to
            # actually call METIS (ICNTL(7)=5) and ParMETIS (ICNTL(28)=2,
            # ICNTL(29)=2).  With a wrong-width METIS bound into the process
            # these crash (SEGV) or fail with INFO(1)=-50, while the default
            # automatic ordering of a small problem may never touch METIS.
            @testset "$ex19_case 1: mumps METIS ordering" begin
                if test_mumps
                    args = `-da_refine 3 -pc_type lu -pc_factor_mat_solver_type mumps -mat_mumps_icntl_7 5`;
                    r = run_petsc_ex(args, 1, ex19_case, mpi_single_core=mpi_single_core)
                    @test r.exitcode == 0
                end
            end
            @testset "$ex19_case 2: mumps ParMETIS ordering" begin
                if test_mumps & is_parallel
                    args = `-da_refine 3 -pc_type lu -pc_factor_mat_solver_type mumps -mat_mumps_icntl_28 2 -mat_mumps_icntl_29 2`;
                    r = run_petsc_ex(args, 2, ex19_case)
                    @test r.exitcode == 0
                end
            end
        end

        # SuperLU_DIST tests with the Int32 executable (the only PetscInt width
        # with SuperLU_DIST support, see test_superlu_dist_int64 above).
        @testset "ex19_32 2: superlu_dist LU" begin
            if test_superlu_dist & is_parallel
                args = `-da_refine 3 -snes_type ksponly -ksp_type preonly -pc_type lu -pc_factor_mat_solver_type superlu_dist`;
                r = run_petsc_ex(args, 2, "ex19_32")
                @test r.exitcode == 0
            end
        end
        @testset "ex19_32 4: superlu_dist LU" begin
            if test_superlu_dist & is_parallel
                args = `-da_refine 3 -snes_type ksponly -ksp_type preonly -pc_type lu -pc_factor_mat_solver_type superlu_dist`;
                r = run_petsc_ex(args, 4, "ex19_32")
                @test r.exitcode == 0
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
    # Same solve with ICNTL(13)=1: MUMPS factorizes the root frontal matrix sequentially, so
    # ScaLAPACK/BLACS are never called.  Diagnostic for the parallel-MUMPS SIGSEGVs on the
    # macOS x86_64 CI runners (2026-09): passing here while the plain run fails points at the
    # SCALAPACK32_jll path.
    @testset "ex42 2: mumps (ICNTL(13)=1, no ScaLAPACK)" begin
        if test_mumps & is_parallel
            args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type lu -stokes_pc_factor_mat_solver_type mumps -stokes_mat_mumps_icntl_13 1`;
            r = run_petsc_ex(args, 2, "ex42")
            @test r.exitcode == 0
        end
    end

    @testset "ex42 2: superlu_dist" begin
        if test_superlu_dist & is_parallel & test_superlu_dist_int64
            args = `-stokes_ksp_monitor_short -stokes_ksp_converged_reason -stokes_pc_type lu -stokes_pc_factor_mat_solver_type superlu_dist `;
            r = run_petsc_ex(args, 2, "ex42")
            @test r.exitcode == 0
        end
    end

    # Regression test for the parallel-MUMPS / ScaLAPACK factorization crash.
    #
    # MUMPS uses ScaLAPACK (libscalapack32) for the root-node LU factorization
    # in `dmumps_facto_root_` -> `pdgetrf_`. With a SCALAPACK32_jll build whose
    # MPI ABI does not match the MPI actually loaded at runtime (e.g. PETSc_jll
    # 3.22.1 pinning SCALAPACK32_jll 2.2.3 (libmpi.12 soname 18.x) while the
    # process loads MPICH_jll 5.0.1 (soname 19.x)), `pdgetrf_`/`pdamax_` SEGV
    # with a null-pointer deref on >=2 ranks. Single-rank MUMPS and superlu_dist
    # (which does not go through ScaLAPACK) are unaffected, so a plain parallel
    # `ex19 -pc_type lu -pc_factor_mat_solver_type mumps` is the cleanest probe.
    # If this fails, suspect a SCALAPACK32_jll <-> MPI ABI mismatch in PETSc_jll.
    @testset "ex19 2: mumps parallel LU (ScaLAPACK regression)" begin
        if test_mumps & is_parallel
            args = `-snes_type ksponly -ksp_type preonly -pc_type lu -pc_factor_mat_solver_type mumps -da_grid_x 16 -da_grid_y 16`;
            r = run_petsc_ex(args, 2, "ex19")
            @test r.exitcode == 0
        end
    end
    @testset "ex19 2: mumps parallel LU (ICNTL(13)=1, no ScaLAPACK)" begin
        if test_mumps & is_parallel
            args = `-snes_type ksponly -ksp_type preonly -pc_type lu -pc_factor_mat_solver_type mumps -da_grid_x 16 -da_grid_y 16 -mat_mumps_icntl_13 1`;
            r = run_petsc_ex(args, 2, "ex19")
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
    @testset "ex4  4: direct mumps (ICNTL(13)=1, no ScaLAPACK)" begin
        if test_mumps & is_parallel
            args  = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 13 -stag_grid_y 8 -pc_type lu -pc_factor_mat_solver_type mumps -mat_mumps_icntl_13 1 -ksp_converged_reason`;
            r = run_petsc_ex(args, 4, "ex4")
            @test r.exitcode == 0
        end
    end

    # Skipped on macOS: SuperLU_DIST's static pivoting is fragile on this small saddle-point
    # (Stokes) matrix.  On macOS (x86_64 and arm64) the 4-rank and 1-rank factorizations give a
    # useless LU (KSP DIVERGED_ITS, no crash) while 2 ranks work; on Linux the PARMETIS/NATURAL
    # column permutations fail the same way.  Not a bug in the JLLs -- see notes 2026-09-11.
    @testset "ex4  4: direct superlu_dist" begin
        if test_superlu_dist & is_parallel & test_superlu_dist_int64 & !Sys.isapple()
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
    @testset "ex4  2: nondim_abf_lu mumps (ICNTL(13)=1, no ScaLAPACK)" begin
        if test_mumps & is_parallel
            args = `-dim 2 -coefficients layers -pc_type fieldsplit -pc_fieldsplit_type schur -ksp_converged_reason -fieldsplit_element_ksp_type preonly  -pc_fieldsplit_detect_saddle_point false -ksp_type fgmres -fieldsplit_element_pc_type none -pc_fieldsplit_schur_fact_type upper -nondimensional -eta1 1e-2 -eta2 1.0 -isoviscous 0 -ksp_monitor -fieldsplit_element_pc_type jacobi -build_auxiliary_operator -fieldsplit_face_pc_type lu -fieldsplit_face_pc_factor_mat_solver_type mumps -stag_grid_x 32 -stag_grid_y 32 -fieldsplit_face_mat_mumps_icntl_13 1`;
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
        if test_superlu_dist & is_parallel & test_superlu_dist_int64
            args = `-dim 3 -coefficients layers -nondimensional -s 16 -custom_pc_mat -pc_type mg -pc_mg_galerkin -pc_mg_levels 2 -mg_levels_ksp_type richardson -mg_levels_pc_type jacobi -mg_levels_ksp_richardson_scale 0.5 -mg_levels_ksp_max_it 20 -mg_coarse_pc_type lu -mg_coarse_pc_factor_mat_solver_type superlu_dist -ksp_converged_reason        `;
            r = run_petsc_ex(args, 2, "ex4")

            @test r.exitcode == 0
        end
    end
    

    @testset "ex19 1: hdf5 viewer" begin
        if test_hdf5
            dir = mktempdir()
            cd(dir) do
                args = `-da_refine 2 -snes_view_solution hdf5:sol.h5`
                r = run_petsc_ex(args, 1, "ex19", mpi_single_core=mpi_single_core)
                @test r.exitcode == 0
                @test is_hdf5_file("sol.h5")
            end
        end
    end

    @testset "ex19 2: hdf5 viewer (parallel MPI-IO)" begin
        if test_hdf5 & is_parallel
            dir = mktempdir()
            cd(dir) do
                args = `-da_refine 2 -snes_view_solution hdf5:sol.h5`
                r = run_petsc_ex(args, 2, "ex19")
                @test r.exitcode == 0
                @test is_hdf5_file("sol.h5")
            end
        end
    end


    @testset "ex19 1: cuda vectors and matrices" begin
        if test_cuda
            args = `-da_refine 3 -dm_vec_type cuda -dm_mat_type aijcusparse -use_gpu_aware_mpi 0 -ksp_type fgmres -pc_type mg`
            r = run_petsc_ex(args, 1, "ex19", mpi_single_core=mpi_single_core)
            @test r.exitcode == 0
        end
    end

    @testset "ex19 2: cuda, parallel" begin
        if test_cuda & is_parallel
            args = `-da_refine 3 -dm_vec_type cuda -dm_mat_type aijcusparse -use_gpu_aware_mpi 0 -ksp_type fgmres -pc_type bjacobi`
            r = run_petsc_ex(args, 2, "ex19")
            @test r.exitcode == 0
        end
    end

    @testset "ex4  1: cuda direct solve on the GPU" begin
        if test_cuda
            args = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 12 -stag_grid_y 7 -dm_vec_type cuda -dm_mat_type aijcusparse -use_gpu_aware_mpi 0 -pc_type lu -pc_factor_mat_solver_type cusparse -ksp_converged_reason`
            r = run_petsc_ex(args, 1, "ex4", mpi_single_core=mpi_single_core)
            @test r.exitcode == 0
        end
    end

end

