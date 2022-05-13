version 1.0

workflow parallelGuppyGPU {
	input {
		# input must be tar files
		Array[File] fast5_tar_files

	}


	# scatter in case multiple tar files are given
	scatter (fast5_tar in fast5_tar_files) {
		call splitFast5s {
			input:
				file_to_split_tar = fast5_tar

		}

		# call guppyGPU on each of the smaller "proportioned" tar files
		scatter (split_fast5_tar in splitFast5s.split_fast5_tar) {
			call guppyGPU {
				input:
					fast5_tar_file = split_fast5_tar
			}
		}

		# ?????
		call concatenateFiles as bamFile {
			input:
				files = guppyGPU.pass_bam,
				file_type = "bam"
		}

		call concatenateFiles as fastqFile {
			input:
				files = guppyGPU.pass_fastq,
				file_type = "fastq"
		}

		call concatenateFiles as summaryFile {
			input:
				files = guppyGPU.summary,
				file_type = "txt"
		}

	}

	# gather??
	output {
		Array[File] bams = bamFile.concatenatedFile
		Array[File] fastqs = fastqFile.concatenatedFile
		Array[File] summaries = summaryFile.concatenatedFile
	}
	
}

task concatenateFiles {
	input {
		Array[File] files
		String file_type

		String dockerImage = "tpesout/hpp_base:latest"

		# runtime
		Int memSizeGB = 85
		Int threadCount = 2
		Int diskSizeGB = 500
		Int gpuCount = 1
		Int maxRetries = 4
		String gpuType = "nvidia-tesla-v100"
		String nvidiaDriverVersion = "418.87.00"
		String zones = "us-west1-b"
	}
	

	command {
		if [[ ${file_type} == "bam" ]]
		then
			samtools merge -o "final.${file_type}" ${sep=" " files}
		else
			cat ${sep=" " files} > "final.${file_type}"
		fi

	}

	output {
		File concatenatedFile = "final.${file_type}"
	}

	runtime {
		memory: memSizeGB + " GB"
		cpu: threadCount
		disks: "local-disk " + diskSizeGB + " SSD"
		gpuCount: gpuCount
		gpuType: gpuType
		maxRetries : maxRetries
		nvidiaDriverVersion: nvidiaDriverVersion
		docker: dockerImage
		zones: zones
	}
}


task splitFast5s {
	input {
		File file_to_split_tar
		Int desired_size_GB

		String dockerImage = "jiminpark/guppy-wdl:latest" 

		# runtime
		Int memSizeGB = 85
		Int threadCount = 2
		Int diskSizeGB = 500
		Int gpuCount = 1
		Int maxRetries = 4
		String gpuType = "nvidia-tesla-v100"
		String nvidiaDriverVersion = "418.87.00"
		String zones = "us-west1-b"
	}

	command <<<
		## Extract tar file to 
		mkdir input
		
		# place all extracted files into directory input
		tar xvf "~{file_to_split_tar}" --directory input

		cd input
		
		OUTPUT_IDX=0
		OUTPUT_DIR=fast5_tar_$OUTPUT_IDX
		mkdir $OUTPUT_DIR
		for FILE in *.fast5
		do
			if [[ $(du -s -BG $OUTPUT_DIR | sed 's/G.*//') > ~{desired_size_GB} ]] 
			then
				tar -czvf fast5_tarball_$OUTPUT_IDX.tar.gz $OUTPUT_DIR/*
				rm -r $OUTPUT_DIR
				OUTPUT_IDX=$(($OUTPUT_IDX + 1))
				OUTPUT_DIR=fast5_tar_$OUTPUT_IDX
				mkdir $OUTPUT_DIR
			fi
			echo $(du -s -BG $OUTPUT_DIR | sed 's/G.*//')
			mv $FILE $OUTPUT_DIR
		done

		# tar remaining directory
		tar -czvf fast5_tarball_$OUTPUT_IDX.tar.gz $OUTPUT_DIR/*

	>>>

	output {
		Array[File] split_fast5_tar = glob("input/*tar.gz")
	}

	runtime {
		memory: memSizeGB + " GB"
		cpu: threadCount
		disks: "local-disk " + diskSizeGB + " SSD"
		gpuCount: gpuCount
		gpuType: gpuType
		maxRetries : maxRetries
		nvidiaDriverVersion: nvidiaDriverVersion
		docker: dockerImage
		zones: zones
	}


}

task guppyGPU {
	
	input {
	
		File fast5_tar_file

		String CONFIG_FILE = "dna_r9.4.1_450bps_modbases_5mc_cg_sup_prom.cfg"
		Int READ_BATCH_SIZE = 250000
		Int q = 250000

		
		String dockerImage = "jiminpark/guppy-wdl:latest" 

		String? additionalArgs


		Int memSizeGB = 85
		Int threadCount = 2
		Int diskSizeGB = 500
		Int gpuCount = 1
		Int maxRetries = 0
		String gpuType = "nvidia-tesla-v100"
		String nvidiaDriverVersion = "418.87.00"
		String zones = "us-west1-b"
	}


	command <<<
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

		## Extract tar file to 
		mkdir input
		
		# place all extracted files into directory input
		tar xvf "~{fast5_tar_file}" --directory input

		mkdir output

		# check if length of "additionalArgs" is zero

		if [[ "~{additionalArgs}" == "" ]]
		then
			ADDITIONAL_ARGS=""
		else
			ADDITIONAL_ARGS="~{additionalArgs}"
		fi


		guppy_basecaller \
			-i input/ \
			-s output/ \
			-c /opt/ont/guppy/data/"~{CONFIG_FILE}" \
			--bam_out \
			-x cuda:all:100% \
			-r \
			--read_batch_size "~{READ_BATCH_SIZE}" \
			-q "~{q}" \
			${ADDITIONAL_ARGS}

	>>>


	output {
		File pass_bam = glob("output/pass/*.bam")[0]
		File pass_fastq = glob("output/pass/*.fastq")[0]
		File summary = glob("output/sequencing_summary.txt")[0]

	}

	runtime {
		memory: memSizeGB + " GB"
		cpu: threadCount
		disks: "local-disk " + diskSizeGB + " SSD"
		gpuCount: gpuCount
		gpuType: gpuType
		maxRetries : maxRetries
		nvidiaDriverVersion: nvidiaDriverVersion
		docker: dockerImage
		zones: zones
	}



}