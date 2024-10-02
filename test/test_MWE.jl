using Test, Pkg, Base.Sys

# BLAS library used here:
using OpenBLAS32_jll, CompilerSupportLibraries_jll


# ensure that we use the correct version of the package 
#Pkg.add(url="https://github.com/boriskaus/PETSc_jll.jl")
#Pkg.add("PETSc_jll")
#using PETSc_jll

#=
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

=#

if !isnothing(mpiexec)
    mpirun = setenv(mpiexec, PETSc_jll.JLLWrappers.JLLWrappers.LIBPATH_env=>PETSc_jll.LIBPATH[]);
else
    mpirun = nothing;
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

function append_libpath(paths::Vector{<:AbstractString}, ENV::Vector{<:AbstractString})
    return join(vcat(paths..., ENV[first(findall(contains.(ENV,"$LIBPATH_env")))]), pathsep)
end


# single processor example
@info "single processor example:"
args = `-da_refine 3 -pc_type mg -ksp_type fgmres`;
cmd = `$(PETSc_jll.ex19_int64_deb())  $args`
cmd = add_LBT_flags(cmd)

r = run(cmd, wait=true);
@test r.exitcode == 0;

# parallel example
@info "mpi example:"
args = `-da_refine 3 -pc_type mg -ksp_type fgmres`;
cores = 2
cmd = `$(mpirun) -n $cores $(PETSc_jll.ex19_int64_deb_path) $args`
cmd = add_LBT_flags(cmd)
r = run(cmd, wait=true);
@test r.exitcode == 0

