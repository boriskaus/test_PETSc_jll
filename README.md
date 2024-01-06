# test_PETSc_jll.jl

This package is a testing framework to develop the BinaryBuilder package `PETSc_jll.jl`, which is a precompiled version of `PETSc`, a widely used library for scientific computing. Once `PETSc_jll` works, it is fairly straightforward to compile and distribute your own codes that rely on PETSc through the BinaryBuilder system. My own interest is in compiling a binary version of our parallel 3D code `LaMEM` to simulate geoscientific processes. Specifically, I want to use `LaMEM` in teaching which ideally requires a binary that works on all modern operating systems as students tend to have a pletoria of systems on their laptops. We succeeded in that some time ago, and have used it with a lot of success in lectures or as part of other codes. Yet, the recent release of julia 1.10 caused problems, and soon my students will have to use `LaMEM` as part the lectures and it is unsustainable to always keep telling them to stick with julia 1.9.

This package is to document the issue, add a testing framework and show results of systematically adding complexity to PETSc builds while using the CI/CD system of github to keep track whether things are working.  



### 1. Challenges with BinaryBuilder

The idea of BinaryBuilder is fantastic and really allows to widely distribute your codes without having to think too much about the operating system. It also becomes rather straightforward to automatically build wrappers from C that allows you to call specific functions directly. If your code does not have too many external dependencies that is great, and using this we could put together a wrapper for [MAGEMin](https://github.com/JuliaBinaryWrappers/MAGEMin_jll.jl) in an afternoon or so (which is fairly easy to maintain).  

Yet things are way more complicated for PETSc, because it can be installed on its own, but also has the possibility to use external packages such as the parallel direct solvers `SuperLU_DIST`, `MUMPS` and can make use of packages such as `HDF5`. For LaMEM we do want to use that as many 2D simulations benefit quite a bit from these solvers.

The main difficulties I see are:

1. Yggdrasil and BinaryBuilder fully relies on dynamic libraries. I understand the idea behind that; the obvious drawback is that it sometimes happens that one of those libraries is updated to a newer version which is no longer compatible with your code which breaks the toolchain.  

2. One of the main reasons for this to happen is that there is **no testing system** for Yggdrasil packages and no CI/CD system. So if one of the many dependencies of `PETSc_jll` is updated, no-one knows that it broke the system until a user reports that it no longer works. There is also no automatic testing versus julia nightly.

3. In the `classical` workflow you would first try to build the library for as many systems as possible, make a pull request to [Yggdrasil]() and only after that is merged (a few hours or days later) you would test this on different systems (for example as part of the `LaMEM.jl` package). [Please note that the BinaryBuilder help pages do describe how to compile it locally or upload local builds to your personal github repository, which I will use below.] 

Whereas PETSc has a very sophisticated build system which downloads the correct versions of all external packages, we are not allowed to use this but should instead link to separate packages of each of the external packages. The reasoning behind this, is that it may otherwise result in clashes if a user installs a version of `libsuperlu_dist.so` (e.g., from `SuperLU_DIST_jll.jl`) whereas a library with the same name is present within the `PETSc_jll.jl` build. 
I do understand the reasoning behind this, but still don't fully get why I'm not allowed to use the `PETSc` installation system and rename the libraries accordingly (say to `libsuperlu_dist_petsc.so` or so). 

Anyways, here we are and I have just spend the last 7 days or so trying to get `PETSc_jll.jl` working again. Likely that is because I am rather incompetent in doing this, and there are certainly many more skilful people out there that can do a better job. Unfortunately, the `PETSc` team itself seems to not want to touch anything julia related (even when the resulting BinaryBuilder packages can also be used perfectly well outside the julia world), or perhaps it is because they are not allowed to use Docker on their work machines. In any case, I'm stuck with doing this so below 

### 2. Towards a testing framework

PETSc itself comes with a very extensive build-in testing system, and also other packages such as `SuperLU_DIST` have build-in tests to check that it works after installing. If you do a basic installation of `PETSc` the last step is a `make check` step which runs a limited amount of tests for some of the options you specified (and will test, for example, whether `mumps` works in case you specified it). In most cases that is done by running `ex19` with different command-line options.
We cannot run this `make check` at the end of the installation processes because of the cross-compilation system BinaryBuilder uses. What we can do, however, is compile a binary of `ex19`:
```
# this is the example that PETSc uses to test the correct installation        
workdir=${libdir}/petsc/${PETSC_CONFIG}/share/petsc/examples/src/snes/tutorials/
make --directory=$workdir PETSC_DIR=${libdir}/petsc/${PETSC_CONFIG} PETSC_ARCH=${target}_${PETSC_CONFIG} ex19
file=${workdir}/ex19
if [[ "${target}" == *-mingw* ]]; then
    if [[ -f "$file" ]]; then
        mv $file ${file}${exeext}
    fi
fi
install -Dvm 755 ${workdir}/ex19${exeext} "${bindir}/ex19${exeext}"
```
and distribute that as executable along with the PETSc libraries:
```
ExecutableProduct("ex19", :ex19)
```

I have done this for a number of examples that are particularly useful for my use cases (`ex4`, `ex42` and `ex62` in some cases). 
Next you can create a [runtests.jl](https://github.com/boriskaus/test_PETSc_jll/blob/main/test/runtests.jl) that runs a bunch of these tests in the `test_PETSc_jll.jl` package, which essentially mimics the `PETSc` testing system. 

We can run this with the officially released versions of `PETSc_jll`, or with a version that we locally compile in our own github repository. The latter is to be preferred while testing installations as we don't need to bother the `Yggdrasil` team with non-working versions.

You can use the local version of `PETSc_jll` instead of the released version  with:
```
Pkg.add(url="https://github.com/boriskaus/PETSc_jll.jl")
using PETSc_jll
```


3. Development workflow


This is to test the PETSc_jll (a precompiled version of PETSc for most modern operating systems) on different versions of julia, along with the precompiled optional packages.

```julia
julia build_tarballs.jl --debug --verbose --deploy="boriskaus/PETSc_jll.jl" aarch64-apple-darwin-libgfortran5-mpi+mpich,x86_64-linux-gnu-libgfortran5-mpi+mpich,x86_64-w64-mingw32-libgfortran5-mpi+microsoftmpi,x86_64-apple-darwin-libgfortran4-mpi+mpich,x86_64-w64-mingw32-libgfortran4-mpi+microsoftmpi,x86_64-linux-gnu-libgfortran4-mpi+mpich
```



