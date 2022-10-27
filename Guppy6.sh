while getopts d:s:c: flag
do
    case "${flag}" in
        d) working_directory=${OPTARG};;
        s) samples_list=${OPTARG};;
		c) cuda_gpu=${OPTARG};;
    esac
done
echo "Working Directory: $working_directory";
echo "Samples List: $samples_list";
echo "Cuda GPU: $cuda_gpu";

# Set the exit code of a pipeline to that of the rightmost command
# to exit with a non-zero status, or zero if all commands of the pipeline exit
set -o pipefail
# cause a bash script to exit immediately when a command fails
set -e
# cause the bash shell to treat unset variables as an error and exit immediately
set -u
# echo each line of the script to stdout so we can see what is happening
# to turn off echo do 'set +o xtrace'
set -o xtrace

while IFS= read -r line
do
	IFS=_ read -r SAMPLE rest <<< "$line"

	IFS=. read -r subsample x y <<< "$rest"

	# create directories
	mkdir -p "$working_directory/input/${SAMPLE}"
	cd "$working_directory/input/${SAMPLE}"

	OUTPUT=$working_directory/output/${SAMPLE}/${SAMPLE}_${subsample}
	mkdir -p ${OUTPUT}

	FINAL_OUTPUT=$working_directory/output/final_output/${SAMPLE}/nanopore
	mkdir -p ${FINAL_OUTPUT}

	# create log file
	log_file=${FINAL_OUTPUT}/Guppy6_${SAMPLE}_${subsample}.log
	echo "Log File - " > $log_file
	echo "sample: " $SAMPLE >> $log_file
	echo "subsample: " $subsample >> $log_file

	# download fast5 tar file from s3 bucket
	aws --no-sign-request s3 cp s3://human-pangenomics/working/HPRC/${SAMPLE}/raw_data/nanopore/${SAMPLE}_${subsample}.fast5.tar $working_directory/input/${SAMPLE}

	# untar fast5 tar file
	tar xvf $working_directory/input/${SAMPLE}/*.tar --directory $working_directory/input/${SAMPLE}

	# remove tar file after untar
	rm $working_directory/input/${SAMPLE}/${SAMPLE}_${subsample}.fast5.tar

	FAST5=$(find $working_directory/input -type d -name "fast5" -print)
	CONFIG_PATH="/opt/ont/guppy/data"

	# call guppy
	guppy_basecaller -i ${FAST5} -s ${OUTPUT} -c ${CONFIG_PATH}/dna_r9.4.1_450bps_modbases_5mc_cg_sup_prom.cfg --bam_out -x cuda:$cuda_gpu -r --read_batch_size 250000 -q 250000 >> $log_file

	# merge bam files and output to final output directory
	echo "merging partial fail bams..."
	time samtools merge -@ 30 ${FINAL_OUTPUT}/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_fail.bam ${OUTPUT}/fail/*.bam >> $log_file

	echo "merging partial pass bams..."
	time samtools merge -@ 30 ${FINAL_OUTPUT}/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_pass.bam ${OUTPUT}/pass/*.bam >> $log_file

	# concatenate fastq files, gzip and output to final output directory
	echo "concatenating partial fail fastqs..."
	time (cat ${OUTPUT}/fail/*.fastq | gzip -c > ${FINAL_OUTPUT}/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_fail.fastq.gz) >> $log_file

	echo "concatenating partial pass fastqs..."
	time (cat ${OUTPUT}/pass/*.fastq | gzip -c > ${FINAL_OUTPUT}/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_pass.fastq.gz) >> $log_file

	# gzip summary file and output to final output directory
	gzip -c ${OUTPUT}/sequencing_summary.txt > ${FINAL_OUTPUT}/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_sequencing_summary.txt.gz

	# clean up files

	COMPLETE=$(find $working_directory/input -type d -name "${SAMPLE}_${subsample}" -print)

	echo "folder to remove: " ${OUTPUT}
	rm -r ${OUTPUT}
	echo "folder to remove: " ${COMPLETE}
	rm -r ${COMPLETE}

done < $samples_list