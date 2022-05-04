version 1.0

#reference: https://github.com/tpesout/megalodon_wdl/blob/main/wdl/megalodon.wdl

workflow callGuppyGPU {
	
	input {
		# input must be tar files
		Array[File] fast5_tar_files
	}

	scatter (fast5_tar in fast5_tar_files) {

		call guppyGPU {
			input:
				fast5_tar = fast5_tar
		}
	}

	output {
		Array[File] bams = guppyGPU.pass_bam
		Array[File] fastqs = guppyGPU.pass_fastq
		Array[File] summaries = guppyGPU.summary
	}

}

task guppyGPU {
	
	input {
	
		File fast5_tar

		String CONFIG_FILE = "dna_r9.4.1_450bps_modbases_5mc_cg_sup_prom.cfg"
		Int READ_BATCH_SIZE = 250000
		Int q = 250000

		
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

		## Extract tar file to 
		mkdir input
		
		tar xvf ${fast5_tar} --directory input

		mkdir output
		cd output

		guppy_basecaller \
			-i input/ \
			-s output/ \
			-c /opt/ont/guppy/data/${CONFIG_FILE} \
			--bam_out \
			-x cuda:all:100% \
			-r \
			--read_batch_size ${READ_BATCH_SIZE} \
			-q ${q}

	}


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
        nvidiaDriverVersion: nvidiaDriverVersion
        docker: dockerImage
        zones: zones
	}



}
