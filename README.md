# test_PETSc_jll

This is to test the PETSc_jll (a precompiled version of PETSc for most modern operating systems) on different versions of julia, along with the precompiled optional packages.

```julia
julia build_tarballs.jl --debug --verbose --deploy="boriskaus/PETSc_jll.jl" aarch64-apple-darwin-libgfortran5-mpi+mpich,x86_64-linux-gnu-libgfortran5-mpi+mpich,x86_64-w64-mingw32-libgfortran5-mpi+microsoftmpi,x86_64-apple-darwin-libgfortran4-mpi+mpich,x86_64-w64-mingw32-libgfortran4-mpi+microsoftmpi,x86_64-linux-gnu-libgfortran4-mpi+mpich
```



