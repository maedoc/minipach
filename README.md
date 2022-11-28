A miniature Pachyderm idea to complement Datalad.

Pach has notion of repos.  You put files into repos, and they're content hashed,
much like Datalad.

Unlike Datalad, Pach lets one define pipelines which are rules that ingest
one or more repos, pattern match over them, run a command on them.  The outputs
go into a new repo named after the pipeline, which might become input data
for another pipeline.  This is not dissimilar to Makefiles, e.g.

```
pipeline:
  name: edges
description: A pipeline that performs image edge detection by using the OpenCV library.
input:
  pfs:
    glob: /*
    repo: images
transform:
  cmd:
    - python3
    - /edges.py
  image: opencv
```

would be in Make something like
```
edges/%: images/%
    docker run -v $<:/input -v $@:/output opencv python3 edges.py
```
except that this is content hashed instead of file name based.

Datalad gives us the content hashing, but we don't have the notion of repos,
unless we start creating some nested datasets:

- repo superdataset
  - datum subdataset 1
  - datum subdataset 2

etc, then a pipeline definition would imply 

- pipeline dataset
  - processed subdataset 1
  - processed subdataset 2

Pach has an orchestrator, we just want to automatically derive a sequence
of jobs that requires running, w/o recomputing results which are already
known.  So, if subdataset 2 has the same content as 1 then proc'd subdataset 2
is just a copy of proc'd sub 1, and the computation happens once.

so we could structure as follows

- raw
  - t1
    - sub-1
    - sub-2
    - sub-3
  - t2
    - sub-1
    - sub-3

a freesurfer rule globs against t1/t2 datasets with
same subject name, with resulting repo

- fs
  - sub-1
  - sub-2
  - sub-3

glob as first pass, then prune keeping unique (sorted?) inputs
since pipeline is immutable.

Such a scheduler can generate the required jobs into a queue,
individual jobs do `datalad run` calls resulting in pulling only
bits of the matching data, and save/push results.

Rules could be defined w/ snakemake but mainly this would be
a convention on how dataset hierachy maps to rules, paired
with a lightweight scheduling machinery + e.g. minio for distributed
storage.

## handling subjects etc

one could use a pipeline only to match together bits of data from other
disparate datasets.  what's the overhead on nested datasets?

**into the terminal for 30 minutes**

yup there's overhead for cleanly modular datasets this way, but so what.

A Makefile is enough to autogenerate intermediate datasets which represent
grouped inputs to a tool like FreeSurfer. I guess snakemake would as well.
Pushing those to a CI could then trigger a set of workers to go through all
that. 

That doesn't give us content-hash driven job running yet, but it does get closer
to the repo idea.  Normalizing various input specs is a good first step, though
doing it with explicit nested datasets is expensive (~500K/dataset, tons of files).

## a different way

another approach would be simpler and take pach repo as closer to git repo: don't
try to dataset each thing, use regular directories in both inputs and outputs.

this means we would not use intermediate datasets to normalize input spec, perhaps
just symbolic links.. much lighter.

yep this is much lighter, and seems reasonable as long as conventions are respected

## hooks 

datalad/git hooks would be a way to trigger the kind of behavior pach has: once a 
`datalad save` is done, the job specs are applied to update the set of waiting jobs.

if enabled, a `datalad save` could result immediate in a `sbatch` job submission
(or lots of them), or just submissions to a web style redis queue.  but if it's not
a shared storage system, it makes more sense to save such automation for push/pull
operations.  e.g. on a push, the queue system is triggered to handle job processing
and the datasets are updated as job results become available.

## still content hashing

still need a clear mechanism to resolve job specs, figure out unique work required.
this could use a subset of pach's syntax, implement as a few hundred line pyhton file.

a pipeline would be implicit in presence of `dir/spec.yml` so ye ol python script just
`glob.glob('*/spec.yml')` and then globs through available data, resolving dependencies
and using datalad's hashes to uniquify work.

it'd also be helpful for the script to automate/validate folder/dataset structure to
lay out quickly a new project or cookiecutter pipelines from existing content like docker
or makefile.

datalad could be used for singularity containers as well... hm. 

## eventing

Ideally we just want to push data into repo and everything happens for us.  If we're using
files and folders, then this could be do with an inotify style mechanism:

https://unix.stackexchange.com/a/323919

```
inotifywait -m /repos -e create -e moved_to |
    while read directory action file; do
        if [[ "$file" =~ .*yml$ ]]; then # Does the file end with .xml?
            minipach schedule jobs  # or whatever
        fi
    done
```
