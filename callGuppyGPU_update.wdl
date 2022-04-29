version 1.0

#reference: https://github.com/tpesout/megalodon_wdl/blob/main/wdl/megalodon.wdl

workflow callGuppyGPU {
	
	input {
		# input must be tar files
		Array[File] fast5_tar_files
	}

	scatter (fast5_tar in fast5_tar_files) {

		call unzipTarFile {
			input:
				tar_file = fast5_tar

		}


		call guppyGPU {
			input:
				FAST5 = unzipTarFile.untar_output
		}

	}
	output {
		Array[File] bams = guppyGPU.pass_bam
		Array[File] fastqs = guppyGPU.pass_fastq
		Array[File] summaries = guppyGPU.summary
	}

}


task unzipTarFile {

	input {
		File tar_file
		Int diskSizeGB = 500
		String zones = "us-west1-b"
		String dockerImage = "tpesout/megalodon:latest"
	}
	
	
	command {
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


		mkdir output
		cd output

		if [[ "${tar_file}" == *.tar ]] || [[ "${tar_file}" == *.tar.gz ]]
		then
			tar xvf ${tar_file}
			echo "true" >../unzipped
		else
			echo "false" >../unzipped
		fi
	}

	output {
		Boolean tar_unzipped = read_boolean("unzipped")
		Array[File] untar_output = glob("output/*")
	}

	runtime {
		memory: "2 GB"
        cpu: 1
        disks: "local-disk " + diskSizeGB + " SSD"
        docker: dockerImage
        preemptible: 1
        zones: zones
	}

}

task guppyGPU {
	
	input {

		Array[File] FAST5
		String OUTPUT_PATH

		File CONFIG_FILE = "dna_r9.4.1_450bps_modbases_5mc_cg_sup_prom.cfg"

		Int READ_BATCH_SIZE = 250000
		Int q = 250000

		### needs to be updated ###
		String dockerImage = "jiminpark/guppy-wdl:latest" 


		# needs to be updated
		Int memSizeGB = 85
		Int threadCount = 12
		Int diskSizeGB = 500
		Int gpuCount = 1
		String gpuType = "nvidia-tesla-v100"
		String nvidiaDriverVersion = "418.87.00"
		String zones = "us-west1-b"
	}

	


	command {
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


		guppy_basecaller \
		-i ${FAST5} \
		-s ${OUTPUT_PATH} \
		-c /opt/ont/guppy/data/${CONFIG_FILE} \
		--bam_out \
		-x cuda:all:100% \
		-r \
		--read_batch_size ${READ_BATCH_SIZE} \
		-q ${q}

	}


	output {
		File pass_bam = "${OUTPUT_PATH}/pass/*.bam"
		File pass_fastq = "${OUTPUT_PATH}/pass/*.fastq"
		File summary = "${OUTPUT_PATH}/sequencing_summary.txt"

	}

	runtime {
		memory: memSizeGB + " GB"
        cpu: threadCount
        disks: "local-disk " + diskSizeGB + " SSD"
       	gpuCount: gpuCount
        gpuType: gpuType
        nvidiaDriverVersion: nvidiaDriverVersion
        docker: dockerImage
        zones: zones
	}



}

