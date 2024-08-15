# test_PETSc_jll.jl
This package is a testing framework to develop the BinaryBuilder package `PETSc_jll.jl`, which is a precompiled version of `PETSc`, a widely used library for scientific computing. Once `PETSc_jll` works, it is fairly straightforward to compile and distribute your own codes that rely on PETSc through the BinaryBuilder system. My own interest is in compiling a binary version of our parallel 3D code `LaMEM` to simulate geoscientific processes. Specifically, I want to use `LaMEM` in teaching which ideally requires a binary that works on all modern operating systems as students tend to have a pletoria of systems on their laptops. We succeeded in that some time ago, and have used it with a lot of success in lectures or as part of other codes. Yet, the recent release of julia 1.10 caused problems, and soon my students will have to use `LaMEM` as part the lectures and it is unsustainable to always keep telling them to stick with julia 1.9.

This package is to document the issue, add a testing framework and show results of systematically adding complexity to PETSc builds while using the CI/CD system of github to keep track whether things are working.  



### 1. Challenges with BinaryBuilder

The idea of BinaryBuilder is fantastic and really allows to widely distribute your codes without having to think too much about the operating system. It also becomes rather straightforward to automatically build wrappers from C that allows you to call specific functions directly. If your code does not have too many external dependencies that is great, and using this we could put together a wrapper for [MAGEMin](https://github.com/JuliaBinaryWrappers/MAGEMin_jll.jl) in an afternoon or so (which is fairly easy to maintain).  

Yet things are way more complicated for PETSc, because it can be installed on its own, but also has the possibility to use external packages such as the parallel direct solvers `SuperLU_DIST`, `MUMPS` and can make use of packages such as `HDF5`. For LaMEM we do want to use that as many 2D simulations benefit quite a bit from these solvers.

The main difficulties I see are:

1. Yggdrasil and BinaryBuilder fully relies on dynamic libraries. I understand the idea behind that; the obvious drawback is that it sometimes happens that one of those libraries is updated to a newer version which is no longer compatible with your code which breaks the toolchain.  

2. The key issue is that there is **no testing system** for Yggdrasil packages and accordingly no CI/CD system. So if one of the many dependencies of `PETSc_jll` is updated, no-one knows that it broke the system until a user reports that it no longer works. There is also no automatic testing versus julia nightly.

3. In the `classical workflow` you would first try to build the library for as many systems as possible, make a pull request to [Yggdrasil]() and only after that is merged (a few hours or days later) you would test this on different systems (for example as part of [LaMEM.jl](https://github.com/JuliaGeodynamics/LaMEM.jl). BinaryBuilder does allow you to [compile it locally](https://docs.binarybuilder.org/dev/building/#Building-a-custom-JLL-package-locally) and/or upload local builds to your [personal github repository](https://docs.binarybuilder.org/dev/FAQ/), which I will use below. 

Whereas PETSc has a very sophisticated build system which downloads the correct versions of all external packages, we can't use it but should instead link to separate packages of each of the external packages. This is because it may otherwise result in clashes if a user installs a version of `libsuperlu_dist.so` (e.g., from `SuperLU_DIST_jll.jl`) whereas a library with the same name is present within the `PETSc_jll.jl` build. 
I do understand the reasoning behind this, but still don't fully get why I'm not allowed to use the `PETSc` installation system and rename the libraries accordingly (say to `libsuperlu_dist_petsc.so` or so). 

Anyways, here we are and I have just spend the last 7 days or so trying to get `PETSc_jll.jl` working again. (Likely that is because I am rather incompetent in doing this, and there are certainly many more skilful people out there that can do a better job. Unfortunately, the `PETSc` team itself seems to not want to touch anything julia related (even when the resulting BinaryBuilder packages can also be used perfectly well outside the julia world), or perhaps it is because they are not allowed to use Docker on their work machines). 

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

I have done this for a number of examples that are particularly useful for me (`ex4`, `ex42` and `ex62` in some cases). 
Next you can create a [runtests.jl](https://github.com/boriskaus/test_PETSc_jll/blob/main/test/runtests.jl) that runs a bunch of these tests in the `test_PETSc_jll.jl` package, which essentially mimics the `PETSc` testing system. 

We can run this either with the officially released versions of `PETSc_jll`, or with a version that we locally compiled and uploaded to our own github repository. The latter is to be preferred while testing installations, as we don't need to bother the `Yggdrasil` team with non-working versions.

You can use the local version of `PETSc_jll` instead of the released version with:
```
Pkg.add(url="https://github.com/boriskaus/PETSc_jll.jl")
using PETSc_jll
```

You can build local versions of the library like this and upload it to your local directory with:

```julia
julia build_tarballs.jl --debug --verbose --deploy="boriskaus/PETSc_jll.jl" aarch64-apple-darwin-libgfortran5-mpi+mpich,x86_64-linux-gnu-libgfortran5-mpi+mpich,x86_64-w64-mingw32-libgfortran5-mpi+microsoftmpi,x86_64-apple-darwin-libgfortran4-mpi+mpich,x86_64-w64-mingw32-libgfortran4-mpi+microsoftmpi,x86_64-linux-gnu-libgfortran4-mpi+mpich,x86_64-apple-darwin-libgfortran5-mpi+mpich
```
Note that I also compile a few additional versions for linux/windows/mac which appear to be the ones that the github CI system uses.

Some things to keep in mind while doing this: 
- You should name your local library as the package (so `"boriskaus/PETSc_jll.jl"` and not `"boriskaus/LibPETSc_jll.jl"`), otherwise you can;t use it later in other packages 
- If you re-compile a package, make sure that the previous release is deleted first on the [github page](https://github.com/boriskaus/PETSc_jll.jl/releases); otherwise it can't upload it  
- Using a powerful machine is helpful.


### 3. Step-wise development of PETSc

At the time of writing (6.1.2024) I was running into the issue that `PETSc_jll` with version 3.20.0 wouldn't even precompile anymore on windows, as can be seen here for [julia 1.9 and windows](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7420510714/job/20192043786). At the same time, a simular testing framework was setup for [SuperLU_DIST_jll](https://github.com/boriskaus/test_SuperLU_DIST_jll) which worked [fine](https://github.com/boriskaus/test_SuperLU_DIST_jll/actions/runs/7422000918/job/20196454722) on windows/mac/linux for julia 1.9-1.11 in serial and parallel for version 8.2.1 which was [merged](https://github.com/JuliaPackaging/Yggdrasil/pull/7890) accordingly. Therefore it is clearly not an issue of the MicrosoftMPI being used. 

Yet, what is the issue? In the following I will stepwise increase the complexity of the installation, while using CI to keep track of whether it works. This is mostly done for myself, but perhaps others may find this useful for theior packages in the futiure


##### Basic installation, no MPI, downloaded BLASLAPACK, windows only
The most basic installation is [build_tarballs_noMPI_downloadBLAS.jl](./build_scripts/build_tarballs_noMPI_downloadBLAS.jl) which we will compile on 1.9/1.10. 

I've compiled the PETSc library with:
```
julia build_tarballs_noMPI_downloadBLAS.jl --debug --verbose --deploy="boriskaus/PETSc_jll.jl" x86_64-w64-mingw32-libgfortran5-mpi+microsoftmpi,x86_64-w64-mingw32-libgfortran4-mpi+microsoftmpi
```

shockingly, not even this [works](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7432642556/job/20224687746). Whereas it did not crash upon precompiling it, it [segfaults](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7432642556/job/20224687746#step:6:136) when running. As we did not compile this version with debug options, we have little info.
As a next step, I activate debugging and compile it for more systems so we can test on linux/mac as well:
```
julia build_tarballs.jl --debug --verbose --deploy="boriskaus/PETSc_jll.jl" aarch64-apple-darwin-libgfortran5-mpi+mpich,x86_64-linux-gnu-libgfortran5-mpi+mpich,x86_64-w64-mingw32-libgfortran5-mpi+microsoftmpi,x86_64-apple-darwin-libgfortran5-mpi+mpich,x86_64-apple-darwin-libgfortran4-mpi+mpich
``` 
Turns out that this works fine on linux/mac but not windows, see [here](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7433190048)

So the mystery remains: why is it failing in windows? It certainly worked fine previously, as LaMEM 1.2.4 compiles fine with [PETSc 3.16.8](https://github.com/JuliaGeodynamics/LaMEM.jl/actions/runs/7349955247/job/20010768089)  and LaMEM 2.1.2 works with [PETSc 3.18.7](https://github.com/JuliaGeodynamics/LaMEM.jl/actions/runs/7349955247/job/20010768089). Yet none of them work with julia 1.10, because of an issue with [libspqr.so.2](https://github.com/JuliaGeodynamics/LaMEM.jl/actions/runs/7349955247/job/20010768089#step:6:41) which appears to be part of SuiteSparse. 
Note that the windows compilation features a problem in [precompilation](https://github.com/JuliaGeodynamics/LaMEM.jl/actions/runs/7391374810/job/20108073568?pr=21#step:6:416).


##### Previous version of PETSc_jll
So what if we test previous versions of PETSc?
A test with PETSc_jll 3.18.6 (and 3.18.7 on julia 1.10, which is in fact a much more recent build) shows that it works fine, apart from julia 1.10 and windows (see [here](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7433265800/job/20226063003)). That confirms what we already saw with LaMEM.jl.

So in other words: PETSc 3.18.6 works on windows for julia 1.9; yet PETSc 3.20.0 does not work on windows & 1.9. Is that because of a version difference in PETSc or because something changed in the BinaryBuilder or julia toolchain that went unnoticed?

##### Rebuilding PETSc_jll 3.18.6
To check this, lets rebuild 3.18.6 using the exact same options as we used last time (May 20 2023). The build file is called `build_tarballs_petsc_3_18_6.jl` and was slighty modified as we need to apply the previous patches (which were all renamed), to restrict the builds to real/Int64 (to speed up compilation) and to add ex19 (default PETSc test)

The first interesting observation is that it no longer compiles, but instead stops with:
```bash
[22:52:31] *******************************************************************************
[22:52:31]          UNABLE to CONFIGURE with GIVEN OPTIONS    (see configure.log for details):
[22:52:31] -------------------------------------------------------------------------------
[22:52:31] You set a value for --with-blaslapack-lib=<lib>, but [''] cannot be used
[22:52:31] *******************************************************************************
[22:52:31] 
[22:52:31] Child Process exited, exit code 1
┌ Warning: Build failed, the following log files were generated:
│   - ${WORKSPACE}/srcdir/petsc-3.18.6/RDict.log
│   - ${WORKSPACE}/srcdir/petsc-3.18.6/configure.log
│   - ${WORKSPACE}/srcdir/petsc-3.18.6/aarch64-apple-darwin20_double_real_Int64/lib/petsc/conf/configure.log
```

That is weird. We are using the same version of BB (0.5.6), so its not that.

Luckily the logfiles of the original build are saved [here](https://github.com/JuliaBinaryWrappers/PETSc_jll.jl/releases/download/PETSc-v3.18.6%2B1/PETSc-logs.v3.18.6.aarch64-apple-darwin-libgfortran5-mpi+mpich.tar.gz), which shows that the original compilation used these compilers:
```
clang version 13.0.1 (/home/mose/.julia/dev/BinaryBuilderBase/deps/downloads/clones/llvm-project.git-1df819a03ecf6890e3787b27bfd4f160aeeeeacd50a98d003be8b0893f11a9be 75e33f71c2dae584b13a7d1186ae0a038ba98838)
Target: arm64-apple-darwin20
Thread model: posix
```
Whereas we now use
```
sandbox:${WORKSPACE}/srcdir/petsc-3.18.6 # cc --version
clang version 16.0.6 (/home/gbaraldi/.julia/dev/BinaryBuilderBase/deps/downloads/clones/llvm-project.git-1df819a03ecf6890e3787b27bfd4f160aeeeeacd50a98d003be8b0893f11a9be 7cbf1a2591520c2491aa35339f227775f4d3adf6)
Target: arm64-apple-darwin20
Thread model: posix
InstalledDir: /opt/x86_64-linux-musl/bin
```

We can fix the clang to 13 with:
```
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               augment_platform_block, 
               julia_compat="1.6", 
               preferred_gcc_version = v"9", 
               preferred_llvm_version=v"13")
```

Another change is that `MPICH` now has version 4.1.2, which used to be 4.1.1. I have not fixed that in the initial build.

With this, we can compile 3.18.6 successfully. Yet, when running the test_suite it fails on 1.10 (SuiteSparse error) and on [windows 1.9](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7438273548/job/20236864198#step:6:169) with:
```
Allocations: 5058579 (Pool: 5053560; Big: 5019); GC: 10
Mingw-w64 runtime failure:
32 bit pseudo relocation at 0000000008C01CEA out of range, targeting 00007FFEA73F6530, yielding the value 00007FFE9E7F4842.
ERROR: LoadError: Package test_PETSc_jll errored during testing (exit code: 3)
Stacktrace:
```
which was also reported by an ongoing compilation of [HDF5_jll](https://github.com/eschnett/Yggdrasil/pull/6) on windows.

Interestingly [SuperLU_DIST_jll](https://github.com/boriskaus/test_SuperLU_DIST_jll/actions/runs/7422000918) works fine on windows & with MPI.

*What changed?*
Let's focus first on windows & 3.18.6 where we have a compilation from May 2023 which works fine and a new compilation with the same parameters which fails. Restricting MPICH to 4.1.1 did not change the situation (somewhat logically as we don't use that on windows).

##### Without clang constraint on windows
Analyzing the run logs a bit more in  detail seems to reveal that windows uses llvm14, whereas we compiled with llvm13. So the next attempt is to do a windows-build only, and remove the clang constraint from this platform. Turns out that this compiles fine, but running gives the same [runtime error](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7594048475/job/20685150138#step:7:221).

Some hints as what this might be can be taken from the [HDF5_jll](https://github.com/JuliaPackaging/Yggdrasil/blob/master/H/HDF5/build_tarballs.jl) build.

That did not [work](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7594145663/job/20685355403) so the next attempt is to use gcc 11 instead, which turns out not to even compile ("Fortran error! mpi_init() could not be located!"). 

As that did not work, the next attempt removed gcc versions altogether and copies symlink. this did not function either.


##### MicrosoftMPI version as the culprit?
The PETSc version of May 2023 did work but if I recompile the same script now, we receive a runtime error. It's not so clear what causes this, but our colleagues @ HDF5_jll seem to find that this is related to [enabling MPI]( https://github.com/eschnett/Yggdrasil/pull/6).

On windows we use MicrosoftMPI, which had a few updates during [the last year](https://github.com/JuliaPackaging/Yggdrasil/commits/e083b0133c68ca3596046eea8dfee55d611b8488/M/MicrosoftMPI/build_tarballs.jl). The original PETSc 3.18.6 we build, must have used [MicrosoftMPI_jll version 10.1.3+3](https://github.com/JuliaBinaryWrappers/MicrosoftMPI_jll.jl/releases) from April 7, 2023. Looking through the logs of the installation on [windows](https://github.com/JuliaBinaryWrappers/PETSc_jll.jl/releases) shows that the version of MicrosoftMPI_jll that we employed is not actually stored. What is shown is this during PETSc installation:
```
MPI:
  Version:    2
  Includes:   -I/workspace/destdir/include
  Libraries:  /workspace/destdir/bin/msmpi.dll
  mpiexec: Not_appropriate_for_batch_systems_You_must_use_your_batch_system_to_submit_MPI_jobs_speak_with_your_local_sys_admin
  MSMPI_VERSION: 0x100
  ``` 


What if that particular build of `MicrosoftMPI` was for some reason compatible with running it with `MicrosoftMPI 10.1.4` (which is now used to run packages), but something broke in later versions of  `MicrosoftMPI`, so we can compile it but receive a runtime error when running?

It doesn't seem possible to specify a detailed sub-build as version (so we cannot use 10.1.3+3, but only 10.1.3, which will use a different default version). The first attempt, therefore, was using 10.1.2. Turns out that whereas it builds with 10.1.2, it runs with 10.1.4 which gives the usual error.

The following attempt used this:
```julia
dependencies = [
    Dependency("MicrosoftMPI_jll"; platforms=filter(Sys.iswindows, platforms), compat="10.1.2 - 10.1.2"),
```

This did load the correct library upon running, but resulted in the [following error](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7601233995/job/20700407517#step:7:163):

```
[9237b28f] + MicrosoftMPI_jll v10.1.2+3

  4 dependencies errored. To see a full report either run `import Pkg; Pkg.precompile()` or load the packages
ERROR: LoadError: InitError: could not load library "C:\Users\runneradmin\.julia\artifacts\c40a6c43d243a924b2a0798b4752b490d61ebf4c\bin\msmpi.dll"
Access is denied. 
```

Another attempt was made to also fix further packages to the ones we had in ~May 2023
```julia
    Dependency("OpenBLAS32_jll", compat="0.3.21 - 0.3.21"),
    Dependency("CompilerSupportLibraries_jll", compat="1.0.4 - 1.0.4"),     # march 7, 2023
```

##### No MPI on windows 
ok, as nothing works lets try without MPI altogether. This finally gives some success (after adapting the tests), as can be seen [here](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7602378455/job/20702870051).

This works, but suitesparse does not work at all (see [here](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7602965554/job/20704131214) ).

Which version of SuiteSparse is PETSc using anyways? To determine this, we looked at the logfiles and it turns out to be 5.13.0

In a next step, I made an attempt to activate MUMPS 5.6.2 as that is a version that is compiled for windows as well. Unfortunately it results in the usual runtime crash.

A new attempt in which I used SuperLU_DIST but not MPI seemed to work (but couldnt be tested as all tests require MPI). One with MPI and Superlu_DIST gave the same [issue](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7603659590/job/20705660211)

Next on the list was removing the SOSUFFIX, which also doesnt change things. 

##### PETSc 3.18.7 without MPI/without SuiteSparse 
PETSc 3.18.7 doesn't actually work with SuiteSparse (as we need 5.13 which does note exist in BB). To ensure that 3.18.7 works again we deactivate MPI on windows and create a new build.

A retrigger with OpenBLAS rather than with libblastrampoline was necessary. It seems that I messed something up in the process as it no longer works on windows.

##### PETSc 3.18.7 without MPI/without SuiteSparse but with LBT
On the request of [Viral Shah](https://github.com/JuliaPackaging/Yggdrasil/pull/7989#issuecomment-1904367926) another attempt was made to compile 3.18.7 with LBT (I believe I did this already but perhaps other things were messed up in the process).
A first compilation was done for windows only which runs [fine](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7614714564). 
To be sure, we added a build for linux/mac/windows in the mix. 

In a first compile I accidentally still used openblas. Next iteration worked better, but results in [segfaults](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7616965141).

This was therefore revoked.

At the end of this saga (at least) PETSc_jll 3.18.7+1 was finally merged with no SuiteSparse, no MPI for windows and no libblastrampoline (which was part of the discussion). See the PR [here](https://github.com/JuliaPackaging/Yggdrasil/pull/7989). 
A final test if the uploaded PETSc from the repo shows that it works in all [cases](https://github.com/boriskaus/test_PETSc_jll/actions/runs/7632348215). Note that on julia 1.9 this still uses PETSc_jll 3.18.6+1, which I suspect is because the first release of 3.18.7 was limited to 3.10.

What deserves more work in the future is trying to use LBT (see comment of Viral Shah @ the end of the PR), which would have the advantage that we can switch BLAS on the fly for PETSc (may bring speed advantages).

##### PETSc 3.18.8 without MPI/without SuiteSparse 
Downstream issues occured with 3.18.7+1 because 3.18.7+0 was compiled with SuiteSparse whereas 3.18.7+1 had no SuiteSparse support. Accordingly, the LaMEM_jll compilation did not work as it was looking for SuiteSparse files. This was resolved by re-releasing it as 3.18.8.


### August 14, 2024 

Given that the last effort took 1.5 months to resolve and I have a rather busy normal job, my motivation for restarting this effort for newer versions of PETSc has been rather small. What was clear from the 2024 PETSc conference, though, is that there is quite some demand for having precompiled libraries that work on all modern OS's.

Examples are Firedrake, where this is the number 1 requested feature. Added complexity with firedrake is that it generates PETSc source files dynamically, so it would need to compile the files on the local system before deploying. Issue with that is that the PETSc compilation system hardcodes the library paths, which are obviously different on each local install.  
Others (e.g. LibCEED developers) are interested to have a PETSc-julia interaction as julia can generate nice GPU kernels.

During the last year, other issues turned up, such as newer versions of MPICH being suddenly incompatible with the various dependencies. The solution of that would have been to pin the version numbers rather than specifying a lower bound. More concretely, in my opinion the current way of linking the various dependencies as external dynamic libraries is a big part of the problem, and makes it too hard to maintain from my side. 

In august (another holiday) a new effort was therefore started to see if I can make a fresh build with a newer version of PETSc, link it to suitesparse and see whether we can download the other external libraries as static, rather than dynamic, libraries. Another goal is to see whether we can use libblastrampoline (LBT)

##### PETSc 3.21 with LBT 
We start with a version that only has LBT but no other dependencies. It compiles fine with:

```julia
julia build_tarballs_3.21.4_LBT.jl --debug --verbose --deploy="boriskaus/PETSc_jll.jl" aarch64-apple-darwin-libgfortran5-mpi+mpich,x86_64-linux-gnu-libgfortran5-mpi+mpich,x86_64-w64-mingw32-libgfortran5-mpi+microsoftmpi,x86_64-apple-darwin-libgfortran4-mpi+mpich,x86_64-w64-mingw32-libgfortran4-mpi+microsoftmpi,x86_64-linux-gnu-libgfortran4-mpi+mpich,x86_64-apple-darwin-libgfortran5-mpi+mpich
```

