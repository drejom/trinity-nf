# trinity-NF

A Nextflow implementation of a Trinity de novo assembly pipeline

[![nextflow](https://img.shields.io/badge/nextflow-%E2%89%A50.17.3-brightgreen.svg)](http://nextflow.io)

## Quick start 

Make sure you have singularity installed and the module loaded.

Install the Nextflow runtime by running the following command:

    $ curl -fsSL get.nextflow.io | bash


When done, you can launch the pipeline execution with Docker by entering the command shown below:

    $ nextflow run drejom/trinity-nf -profile test

By default the pipeline is executed against the provided example dataset. 
Check the *Pipeline parameters*  section below to see how enter your data on the program 
command line.     
    


## Pipeline parameters

#### `--reads` 
   
* Specifies the location of the reads *fastq* file(s).
* Multiple files can be specified using the usual wildcards (*, ?), in this case make sure to surround the parameter string
  value by single quote characters (see the example below)
* It must end in `.fq.gz`.
* By default it is set to the trinity-nf's location: `../data/fastq/*_{1,2}.fq.gz`

Example: 

    $ nextflow run drejom/trinity-nf -resume

This will handle each fastq file as a seperate sample.

Read pairs of samples can be specified using the glob file pattern. Consider a more complex situation where there are three samples (A, B and C) being paired ended reads. The read files could be:
    
    sample_A_1.fq.gz
    sample_A_2.fq.gz
    sample_B_1.fq.gz
    sample_B_2.fq.gz
    sample_C_1.fq.gz
    sample_C_2.fq.gz

The reads may be specified as below:

    $ nextflow run drejom/trinity-nf --reads '/home/dataset/sample_*_{1,2}.fq.gz'    


#### `--output` 
   
* Specifies the folder where the results will be stored for the user.  
* It does not matter if the folder does not exist.
* By default is set to lncRNA-Annotation-NF's folder: `./results` 

Example: 

    $ nextflow run drejom/trinity-nf --output /home/user/my_results 
  


## Cluster support

trinity-NF execution relies on the [Nextflow](http://www.nextflow.io) framework which provides an 
abstraction between the pipeline functional logic and the underlying processing system.

Thus it is possible to execute it on your computer or any cluster resource
manager without modifying it.

Currently the following platforms are supported:

  + Oracle/Univa/Open Grid Engine (SGE)
  + Platform LSF
  + SLURM
  + PBS/Torque


By default the pipeline is parallelized by spanning multiple threads in the machine where the script is launched.

To submit the execution to a SGE cluster create a file named `nextflow.config`, in the directory
where the pipeline is going to be launched, with the following content:

    process {
      executor='sge'
      queue='<your queue name>'
    }

In doing that, tasks will be executed through the `qsub` SGE command, and so your pipeline will behave like any
other SGE job script, with the benefit that *Nextflow* will automatically and transparently manage the tasks
synchronisation, file(s) staging/un-staging, etc.

Alternatively the same declaration can be defined in the file `$HOME/.nextflow/config`.

To lean more about the avaible settings and the configuration file read the 
[Nextflow documentation](http://www.nextflow.io/docs/latest/config.html).
  
  
Dependencies 
------------

 * Nextflow (0.17.4 or higher)
 * Singularity - https://sylabs.io/singularity/
