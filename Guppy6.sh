






while IFS= read -r line
do
	IFS=_ read -r SAMPLE rest <<< "$line"
	echo $SAMPLE
	IFS=. read -r subsample x y <<< "$rest"
	echo $subsample

	mkdir -p "/data/jimin/input/${SAMPLE}"
	cd "/data/jimin/input/${SAMPLE}"

	# download fast5 tar file from s3 bucket
	aws --no-sign-request s3 cp s3://human-pangenomics/working/HPRC/${SAMPLE}/raw_data/nanopore/${SAMPLE}_${subsample}.fast5.tar .

	# untar fast5 tar file
	tar xvf *.tar --directory ${SAMPLE}

	FAST5=$(find /data/jimin/input -type d -name "fast5" -print)
	OUTPUT=/data/jimin/output/${SAMPLE}/${SAMPLE}_${subsample}
	CONFIG_PATH="/opt/ont/guppy/data"

	mkdir -p ${OUTPUT}

	guppy_basecaller -i ${FAST5} -s ${OUTPUT} -c ${CONFIG_PATH}/dna_r9.4.1_450bps_modbases_5mc_cg_sup_prom.cfg --bam_out -x cuda:0 -r --read_batch_size 250000 -q 250000

	# merge bam files and output to final output directory
	samtools merge -@ 30 /data/jimin/output/final_output/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_fail.bam ${OUTPUT}/fail/*.bam

	rm ${OUTPUT}/fail/*.bam

	samtools merge -@ 30 /data/jimin/output/final_output/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_pass.bam ${OUTPUT}/pass/*.bam

	rm ${OUTPUT}/pass/*.bam

	# concatenate fastq files, gzip and output to final output directory
	cat *.fastq | gzip -c > /data/jimin/output/final_output/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_fail.fastq.gz

	rm ${OUTPUT}/fail/*.fastq

	cat *.fastq | gzip -c > /data/jimin/output/final_output/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_pass.fastq.gz

	rm ${OUTPUT}/pass/*.fastq

	# gzip 
	gzip -c ${OUTPUT}/sequencing_summary.txt > /data/jimin/output/final_output/${SAMPLE}_${subsample}_Guppy_6.3.7_5mc_cg_sup_prom_sequencing_summary.txt.gz


done < fast5_list.txt