# Probe matrix for the parallel-MUMPS / SuperLU_DIST failures of PETSc_jll 3.25.4 on macOS
# (2026-09; identical on the x64 CI runners under Rosetta and on a native arm64 MacBook).
#
# Run from the package directory, after `git pull`:
#     julia --project=. test/macos_probe.jl 2>&1 | tee probe_$(uname -m).log
# and send probe_*.log back.  Runs ~25 short variants of the smallest failing case
# (ex19, 16x16 grid, 2 ranks, MUMPS LU) plus a few SuperLU_DIST variants, each in a few
# seconds, and prints a PASS/FAIL table with the first PETSc error line.
using Pkg
Pkg.instantiate()
haskey(ENV, "PETSC_JLL_LOCAL_PATH") || Pkg.add(url="https://github.com/boriskaus/MUMPS_jll.jl")
haskey(ENV, "PETSC_JLL_LOCAL_PATH") || Pkg.add(url="https://github.com/boriskaus/PETSc_jll1.jl")
using PETSc_jll, CompilerSupportLibraries_jll, OpenBLAS32_jll

@show Base.BinaryPlatforms.HostPlatform()
@show PETSc_jll.host_platform
run(`sw_vers`); run(`sysctl -n machdep.cpu.brand_string`); run(`sysctl -n hw.ncpu`)

const shlib_ext = Sys.isapple() ? "dylib" : "so"
const LIBPATH_env = PETSc_jll.JLLWrappers.JLLWrappers.LIBPATH_env
mpi = isdefined(PETSc_jll, :MPICH_jll) ? PETSc_jll.MPICH_jll : PETSc_jll.OpenMPI_jll
mpiexec = mpi.mpiexec()
println("MPI: ", nameof(mpi)); run(`$(mpiexec) --version`)

libdirs = unique(vcat(CompilerSupportLibraries_jll.LIBPATH_list...))
ilp64 = joinpath(Sys.BINDIR, "..", "lib", "julia", "libopenblas64_.$shlib_ext")
baseenv = Dict(
    LIBPATH_env => join(vcat(PETSc_jll.LIBPATH[], mpi.LIBPATH[], libdirs), ':'),
    "LBT_DEFAULT_LIBS" => join((ilp64, OpenBLAS32_jll.libopenblas_path), ';'),
    "OMP_NUM_THREADS" => "1", "VECLIB_MAXIMUM_THREADS" => "1", "OPENBLAS_NUM_THREADS" => "1",
)

exe(name) = name == "ex19" ? PETSc_jll.ex19_int64_deb().exec[1] :
            name == "ex19_32" ? PETSc_jll.ex19_int32().exec[1] :
            name == "ex4" ? PETSc_jll.ex4().exec[1] : error(name)

function probe(label, ex, n, args; env=Dict{String,String}(), show=false)
    cmd = `$(mpiexec) -n $n $(exe(ex)) $args`
    cmd = addenv(cmd, merge(baseenv, env))
    out = IOBuffer()
    ok = success(pipeline(ignorestatus(cmd); stdout=out, stderr=out))
    txt = String(take!(out))
    err = something(findfirst(l -> occursin(r"PETSC ERROR: (Caught signal|[A-Z][a-z].*)|MUMPS error|INFOG?\(1\)|DIVERGED|Abort\(", l),
                              split(txt, '\n')), nothing)
    firsterr = err === nothing ? "" : strip(split(txt, '\n')[err])
    println(rpad(label, 62), ok ? "PASS" : "FAIL", "  ", first(firsterr, 90))
    show && println(txt)
    return ok
end

base = `-snes_type ksponly -ksp_type preonly -pc_type lu -pc_factor_mat_solver_type mumps -da_grid_x 16 -da_grid_y 16`
println("\n=== ex19 (Int64), 2 ranks, MUMPS LU, 16x16 grid: MUMPS settings ===")
probe("control (fails on macOS CI)",            "ex19", 2, base)
probe("1 rank (control, should pass)",          "ex19", 1, base)
probe("3 ranks",                                "ex19", 3, base)
probe("4 ranks",                                "ex19", 4, base)
probe("ICNTL(28)=2 ICNTL(29)=2 parallel ParMETIS ordering", "ex19", 2, `$base -mat_mumps_icntl_28 2 -mat_mumps_icntl_29 2`)
probe("ICNTL(28)=2 ICNTL(29)=1 parallel PT-SCOTCH? (may be unavailable)", "ex19", 2, `$base -mat_mumps_icntl_28 2 -mat_mumps_icntl_29 1`)
probe("ICNTL(28)=1 ICNTL(7)=5 sequential METIS",  "ex19", 2, `$base -mat_mumps_icntl_28 1 -mat_mumps_icntl_7 5`)
probe("ICNTL(7)=0 AMD",                          "ex19", 2, `$base -mat_mumps_icntl_7 0`)
probe("ICNTL(7)=2 AMF",                          "ex19", 2, `$base -mat_mumps_icntl_7 2`)
probe("ICNTL(7)=4 PORD",                         "ex19", 2, `$base -mat_mumps_icntl_7 4`)
probe("ICNTL(7)=6 QAMD",                         "ex19", 2, `$base -mat_mumps_icntl_7 6`)
probe("ICNTL(13)=1 no ScaLAPACK",                "ex19", 2, `$base -mat_mumps_icntl_13 1`)
probe("ICNTL(14)=500 6x workspace",              "ex19", 2, `$base -mat_mumps_icntl_14 500`)
probe("ICNTL(24)=1 null-pivot detection",        "ex19", 2, `$base -mat_mumps_icntl_24 1`)
probe("CNTL(1)=0 no numerical pivoting",         "ex19", 2, `$base -mat_mumps_cntl_1 0.0`)
probe("ICNTL(22)=1 out-of-core",                 "ex19", 2, `$base -mat_mumps_icntl_22 1`)
probe("ICNTL(35)=0 no BLR (default)",            "ex19", 2, `$base -mat_mumps_icntl_35 0`)
probe("ICNTL(16)=1 single OpenMP thread",        "ex19", 2, `$base -mat_mumps_icntl_16 1`)
probe("-mat_mumps_use_omp_threads 1",            "ex19", 2, `$base -mat_mumps_use_omp_threads 1`)
probe("Int32 build, control",                    "ex19_32", 2, base)
probe("Int32 build, ICNTL(28)=2 ICNTL(29)=2",    "ex19_32", 2, `$base -mat_mumps_icntl_28 2 -mat_mumps_icntl_29 2`)
println("\n=== same case, environment probes ===")
probe("MallocScribble+GuardEdges (macOS malloc debugging)", "ex19", 2, base;
      env=Dict("MallocScribble"=>"1", "MallocGuardEdges"=>"1", "MallocPreScribble"=>"1", "MallocErrorAbort"=>"1"))
probe("MPICH shared memory off (MPIR_CVAR_NOLOCAL=1)",     "ex19", 2, base; env=Dict("MPIR_CVAR_NOLOCAL"=>"1"))
probe("MPICH ch4 posix eager off (MPIR_CVAR_CH4_OFI_ENABLE_SHM? ignored if n/a)", "ex19", 2, base; env=Dict("MPIR_CVAR_CH4_SHM_POSIX_EAGER"=>"none"))
probe("MPICH async progress off",                          "ex19", 2, base; env=Dict("MPIR_CVAR_ASYNC_PROGRESS"=>"0"))
probe("HYDRA_LAUNCHER=fork? (mpiexec local)",              "ex19", 2, base; env=Dict("HYDRA_LAUNCHER"=>"fork"))
println("\n=== verbose failing run (MUMPS ICNTL(4)=3, PETSc -malloc_debug) ===")
probe("verbose", "ex19", 2, `$base -mat_mumps_icntl_4 3 -malloc_debug`; show=true)

println("\n=== ex4 (Int64), SuperLU_DIST, 13x8 staggered grid ===")
sbase = `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 13 -stag_grid_y 8 -pc_type lu -pc_factor_mat_solver_type superlu_dist -ksp_converged_reason`
probe("4 ranks control (fails on macOS CI: DIVERGED_ITS)", "ex4", 4, sbase)
probe("2 ranks",                                          "ex4", 2, sbase)
probe("1 rank",                                           "ex4", 1, sbase)
probe("4 ranks, colperm METIS_AT_PLUS_A",  "ex4", 4, `$sbase -mat_superlu_dist_colperm METIS_AT_PLUS_A`)
probe("4 ranks, colperm PARMETIS",         "ex4", 4, `$sbase -mat_superlu_dist_colperm PARMETIS`)
probe("4 ranks, colperm NATURAL",          "ex4", 4, `$sbase -mat_superlu_dist_colperm NATURAL`)
probe("4 ranks, rowperm NOROWPERM",        "ex4", 4, `$sbase -mat_superlu_dist_rowperm NOROWPERM`)
probe("4 ranks, no equilibration",         "ex4", 4, `$sbase -mat_superlu_dist_equil false`)
probe("4 ranks, 2x2 process grid",         "ex4", 4, `$sbase -mat_superlu_dist_r 2 -mat_superlu_dist_c 2`)
probe("4 ranks, 4x1 process grid",         "ex4", 4, `$sbase -mat_superlu_dist_r 4 -mat_superlu_dist_c 1`)
probe("4 ranks, MPICH shared memory off",  "ex4", 4, sbase; env=Dict("MPIR_CVAR_NOLOCAL"=>"1"))
probe("4 ranks, MUMPS instead (control)",  "ex4", 4, `-dim 2 -coefficients layers -nondimensional 0 -stag_grid_x 13 -stag_grid_y 8 -pc_type lu -pc_factor_mat_solver_type mumps -ksp_converged_reason`)
println("\nDONE")
