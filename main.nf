/*
 * Copyright (c) City of Hope and the authors.
 *
 *   This file is part of 'trinity-nf'.
 *
 *   trinity-nf is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   trinity-nf is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with trinity-nf.  If not, see <http://www.gnu.org/licenses/>.
 */

/* 
 * Main trinity-nf pipeline script
 *
 * @authors
 * Denis O'Meally <domeally.coh.org>
 */




log.info "trinity assembly - N F  ~  version 0.1"
log.info "====================================="
log.info "name                   : ${params.name}"
log.info "forward reads          : ${params.forward}"
log.info "reverse reads          : ${params.reverse}"
log.info "bt2 index              : ${params.bt2index}"	
log.info "annotation             : ${params.annotation}"
log.info "output                 : ${params.output}"
log.info "\n"


/*
 * Input parameters validation
 */

annotationFile         = file(params.annotation)
bt2_index              = file("${params.bt2index}.fa")	
bt2_indices            = Channel.fromPath( "${params.bt2index}*.bt2" ).toList()

/*
 * validate input files/
 */

if( !annotationFile.exists() ) exit 1, "Missing annotation file: ${annotationFile}"

/*
 * Create a channel for read files 
 */
 
Channel
    .fromPath( params.forward )
    .ifEmpty { error "Cannot find any reads matching: ${params.forward}" }
    .set { forward_read_files } 
Channel
    .fromPath( params.reverse )
    .ifEmpty { error "Cannot find any reads matching: ${params.reverse}" }
    .set { reverse_read_files } 
Channel
    .fromFilePairs( params.pairs, size: 2)
    .ifEmpty { exit 1, "Cannot find any reads matching: ${params.pairs}" }
    .set { read_files_fastqc }



/*
 * STEP 1A - FastQC
 */
process fastqc_raw_reads {
    tag "$name"
    container "quay.io/biocontainers/fastqc:0.11.8--1"
    cpus 2
    memory 2.GB

    publishDir "${params.output}/fastqc_rawdata", mode: 'copy',
        saveAs: {filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

    input:
    set val(name), file(reads) from read_files_fastqc

    output:
    file "*_fastqc.{zip,html}" into fastqc_results

    script:
    """
    fastqc -q $reads
    """
}

/*
 * STEP 1b - rCorrector
 */

process rCorrector {
    tag "all_reads"
    container "quay.io/biocontainers/rcorrector:1.0.4--h8b12597_1"
    cpus 28
    memory 40.GB
    time = 12.h
    publishDir "${params.output}/rCorrector_reads", mode: 'copy'


    input:
    file forward_list from forward_read_files.toSortedList()
    file reverse_list from reverse_read_files.toSortedList()

    output:
    set file("*_R1.cor.fq.gz"), file("*_R2.cor.fq.gz") into correctedReads mode flatten
    
    script:
    
    """
    run_rcorrector.pl -t ${task.cpus} -1 ${forward_list.join(',')} -2 ${reverse_list.join(',')} 
    """

}


/*
 * STEP 2 - FilterUncorrectable
 */
process FilterUncorrectable {
    tag "$name"
    cpus 1
    memory 1.GB
    publishDir "${params.output}/rCorrector_reads_filtered", mode: 'copy'


    input:
    set file(read1), file(read2) from correctedReads

    output:
    set val(name), file("un*R1.cor.fq.gz"), file("un*R2.cor.fq.gz") into correctedFilteredReads mode flatten

    script:
   	name = read1.toString() - ~/(.R1)?(_R1)?(_1)?(_trimmed)?(\.cor)?(\.fq)?(\.fastq)?(\.gz)?$/ 

        """
       python2 $workflow.projectDir/bin/FilterUncorrectabledPEfastq.py -1 $read1 -2 $read2 -s $name
       gzip *.fq
        """
    }


/*
 * STEP 3 - Trim Galore!
 */
process trim_galore {
    tag "$name"
    container "dukegcb/trim-galore:latest"
    cpus 2
    memory 16.GB

publishDir "${params.output}/trim_galore", mode: 'copy',
        saveAs: {filename ->
            if (filename.indexOf("_fastqc") > 0) "FastQC/$filename"
            else if (filename.indexOf("trimming_report.txt") > 0) "logs/$filename"
            else null
        }

    input:
    set val(name), file(read1), file(read2) from correctedFilteredReads

    output:
    set val(name), file("*R1.fq.gz"), file("*R2.fq.gz") into filteredCorrectedTrimmedReads mode flatten
    file "*trimming_report.txt" into trimgalore_results


    script:
    
        """
        trim_galore --paired --fastqc --gzip --length 25 $read1 $read2
        """
    }

/*
 * STEP 4 - filter-rRna
 */
process filter_rRNA {

    tag "$name"
    cpus 12
    memory 12.GB
    container "quay.io/biocontainers/bowtie2:2.2.4--py36h6bb024c_4"
    publishDir "${params.output}/rRNA_filtered_reads_bowtie2", mode: 'copy'


/* pinched rRNA SILVA databases from /usr/share/rRNA_databases
* in bschiffthaler/ngs
* concatenated each and sed 's/U/T/g' 
* then Bowtie2 index 
* https://hub.docker.com/r/bschiffthaler/ngs
*/


    input:
    set val(name), file(read1), file(read2) from filteredCorrectedTrimmedReads
    file index from bt2_index
    file bt2_indices
    
    output:
    set val(name), file("*_paired_unaligned_*R1.fq.gz"), file("*_paired_unaligned_*R2.fq.gz") into cleanReads_fastqc mode flatten
    set val("pair1"), file("*_paired_unaligned_*R1.fq.gz") into cleanReads_forward
    set val("pair2"), file("*_paired_unaligned_*R2.fq.gz") into cleanReads_reverse

    script:
    index_base = index.toString() - '.fa'

        """
        bowtie2 --quiet --very-sensitive-local --phred33  --threads ${task.cpus} \\
        -x $index_base  -1 $read1 -2 $read2  --met-file ${name}_bowtie2_metrics.txt \\
        --al-conc-gz blacklist_paired_aligned_${name}_%.fq.gz \\
        --un-conc-gz rRNA_paired_unaligned_${name}_%.fq.gz  \\
        --al-gz blacklist_unpaired_aligned_${name}.fq.gz \\
        --un-gz blacklist_unpaired_unaligned_${name}.fq.gz
        bowtie2 --version        
        """
    }

/*
 * STEP 5 - FastQC on cleaned reads
 */
process fastqc_cleaned_reads {
    tag "$name"
    container "quay.io/biocontainers/fastqc:0.11.8--1"
    cpus 2
    memory 2.GB

    publishDir "${params.output}/fastqc_cleandata", mode: 'copy',
        saveAs: {filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

    input:
    set val(name), file(read1), file(read2) from cleanReads_fastqc

    output:
    file "*_fastqc.{zip,html}" into fastqc_results_cleandata

    script:
    """
    fastqc -q $read1 $read2
    """
}

/*
 * STEP 6 - trinity assembly
 */
process trinity {
    tag "Assembly"
    container "trinityrnaseq/trinityrnaseq:2.8.6"
    cpus 40
    memory 120.GB
    time = 48.h

    publishDir "${params.output}/trinity", mode: 'copy',
        saveAs: {filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename"}

    input:
    set val(forward), file(forward) from cleanReads_forward.groupTuple()
    set val(reverse), file(reverse) from cleanReads_reverse.groupTuple()
    

    output:
    file "trinity_out_dir/Trinity.fasta" into trinity_results

    script:
    def read1list = forward.join(',')
    def read2list = reverse.join(',')
    """
    Trinity \\
      --seqType fq --left $read1list --right $read2list --SS_lib_type RF \\
      --max_memory ${task.memory.giga}G --CPU ${task.cpus} --output trinity_out_dir    
      """
}




//fastqc_results_cleandata.subscribe { println it }
// ===================== UTILITY FUNCTIONS ============================


/* 
 * Helper function, given a file Path 
 * returns the file name region matching a specified glob pattern
 * starting from the beginning of the name up to last matching group.
 * 
 * For example: 
 *   readPrefix('/some/data/file_alpha_1.fa', 'file*_1.fa' )
 * 
 * Returns: 
 *   'file_alpha'
 */
 
def readPrefix( Path actual, template ) {

    final fileName = actual.getFileName().toString()

    def filePattern = template.toString()
    int p = filePattern.lastIndexOf('/')
    if( p != -1 ) filePattern = filePattern.substring(p+1)
    if( !filePattern.contains('*') && !filePattern.contains('?') ) 
        filePattern = '*' + filePattern 
  
    def regex = filePattern
                    .replace('.','\\.')
                    .replace('*','(.*)')
                    .replace('?','(.?)')
                    .replace('{','(?:')
                    .replace('}',')')
                    .replace(',','|')

    def matcher = (fileName =~ /$regex/)
    if( matcher.matches() ) {  
        def end = matcher.end(matcher.groupCount() )      
        def prefix = fileName.substring(0,end)
        while(prefix.endsWith('-') || prefix.endsWith('_') || prefix.endsWith('.') ) 
          prefix=prefix[0..-2]
          
        return prefix
    }
    
    return fileName
}

