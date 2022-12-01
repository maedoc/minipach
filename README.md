A miniature Pachyderm idea to complement Datalad.

## Datalad YODA principles

https://handbook.datalad.org/en/latest/basics/101-127-yoda.html

- use modular hierarchical datasets 
  - but ~300k overhead per repo, so compression is helpful)
  - use compression and lazy fetch when possible
- keep containers for steps & use for run-record
- 


## Pachyderm principles

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

A "cloud-native" solution example would be Argo Workflows.

## scaling complexity

One of the goals is to find a way to smoothly scale complexity: Pachyderm
is nice but requires a kubernetes cluster.  On a Slurm system with shared
storage, the approach will be completely different.  On a local machine,
it's again another story. 

What doesn't usually change

- the datasets
- the computation to do
- the results

What is changing across deployments

- storage
- scheduling
- parallelism

The goal here is to use the same tools locally and on clusters (hpc or k8s).
Some contraints take into account to get benefits:

- transactional versioned data w/ provenance => datalad or s3git
- shared metadata tracking => gitea
- storage is not shared => adopt object store w/ minio or ceph or whatever
- scheduling diverse => snakemake or dask or slurm or ci system
- data driven => gitea/minio notifications, inotify, ci system

Each of these contraints can be relaxed w/o compromising the whole idea, but
a full running example w/ datalad, snakemake, gitea & minio would require
just a Python env for datalad & the gitea & minio binaries, installable in
single 2GB container or multiple or just in a $PREFIX or a user $HOME.

## Tools

We can look at each tool itself to see the haves and have-nots:

### Datalad by itself

Datalad by itself is great for transactional data and provenance, but doesn't
provide compute scheduling, storage, centralized metadata.

### Snakemake by itself

Snakemake describes and runs workflows, but doesn't provide transactional versioning of data.  It
doesn't orchestrate compute but can talk to schedulers (HPC & K8s) and deal with remote
storage.

### s3/minio by itself

Object storage is easier and cheaper than shared filesystems and can notify when data is modified,
but doesn't provide compute.

### Gitea/GitLab/GitHub

These centralize metadata and project management, can notify on changes to datalad repo, but doesn't
provide compute scheduling or data provenance. 

## Tool combinations

It's not obvious that all tools are needed.  For many users, the extra complexity may not
be warranted.

### Pachyderm

Namesake of this repo, provides transactional versioned data (xdvc), workflows, sharing, scaling, but it's neither open source nor free and only runs on k8s. 

### Snakemake and Gitea/GitHub/GitLab

This is probably a frequently used combination: workflow scheduling and code sharing, but data versioning and sharing are ad-hoc.

### Datalad and Snakemake

xvdc & workflows, but only with local copy on local resources.  Scaling
and/or sharing is ad-hoc.

### Datalad + minio

xdvc + scalable storage, but workflow scheduling or centralized metadata is ad-hoc.

### Datalad + Gitea et al

xdvc + centralized metadata but workflows or large file support is ad-hoc

### Snakemake/object storage/Gitea

Centralized code, workflows etc but data versioning is ad-hoc and recording provenance from snakemake is ad-hoc.

### Object storage and Gitea/GitHub

this is datalad the manual way, but workflow & provenance are ad-hoc.

## Example

A worked example for local use (see Dockerfile for all software) would go like this

- start minio server & create bucket for datalad files
- start gitea server for git repos
- configure datalad repo w/ minio bucket as storage
- commit raw data into datalad repo
- push commits to gitea (which pushes files to minio)

so far, no workflow is defined, this looks like a datalad repo available
to other machines on the local network.  Usually at this point, a user
needs to invoke workflows by hand (maybe via `datalad run`).

- add workflow sources (Makefile, snake, sbatch script whatever)
- datalad run workflows.sh
- push results to repo

If we push more/new/changed data to the repo, new or update results are not
automatically computed. This seems like a minor point when a user is developing
the workflow and constantly testing, but over time, it can cause skew between
what's been computed and what's be written in the workflow.

The final step is to ensure that datalad commits automatically result in workflow
execution. A few options

- git or datalad pre-commit hook to run the workflow
- gitea/github web hook notification on commit, to a job queue 
- gitea/github ci-style system which invokes datalad run & snakemake to schedule/scale
  - simple python-based ci runner https://github.com/DavesCodeMusings/tea-runner/wiki#understanding-how-tea-runner-works
A nuance of this step is that each commit potentially results in a second "results
data" commit, except maybe a pre-commit hook option.

## Files only please

Maybe starting networked servers is a problem. The above simplifies to

- no gitea, just a plain git repo
- no minio, just git-annex to track big files
- no ci server or web hook, just a datalad hook, inotifywait- or watch-driven workflow exec
