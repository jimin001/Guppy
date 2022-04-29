workflow callGuppyGPU {
	# takes in fast5.tar or array of fast5 files
	Array[File] fast5_or_tar

	# unzip in the case of tar file
	scatter(inputFile in fast5_or_tar){
		call unzipTarFile {
			input: 
				tarfile=inputFile
		}

		# unzipped array of fast5 files
		Array[File] fast5s = if unzipTarFile.tar_unzipped then unzipTarFile.untar_output else fast5_or_tar


		call guppyGPU {
			input:
				FAST5 = fast5s

		}
	}

}


task unzipTarFile {
	File tarfile

	command {
		mkdir output
		cd output

		if [[ "${tarfile}" == *.tar ]] || [[ "${tarfile}" == *.tar.gz ]]
		then
            tar xvf ${tarfile}
            echo "true" >../unzipped
        else
            echo "false" >../unzipped
        fi
	}

	output {
		Boolean tar_unzipped = read_boolean("unzipped")
		Array[File] untar_output = glob("output/*")
	}

}


task guppyGPU {
	
	Array[File] FAST5
	String OUTPUT_PATH

	String? CONFIG_PATH
	File CONFIG_FILE = "dna_r9.4.1_450bps_modbases_5mc_cg_sup_prom.cfg"

	Int READ_BATCH_SIZE = 250000
	Int q = 250000

	### needs to be updated ###
	String dockerImage = "guppy_gpu:latest" 


	Int memSizeGB = 500
	Int threadCount = 12
	Int diskSizeGB = 128
	Int gpuCount = 1
	String gpuType = "nvidia-tesla-v100"
	String nvidiaDriverVersion = "418.87.00"
	String zones = "us-west1-b"


	command {

		guppy_basecaller \
		-i ${FAST5} \
		-s ${OUTPUT_PATH} \
		-c ${CONFIG_PATH}/${CONFIG_FILE} \
		--bam_out \
		-x cuda:all:100% \
		-r \
		--read_batch_size ${READ_BATCH_SIZE} \
		-q ${q}

	}


	output {
		File pass_bam = "${OUTPUT_PATH}/pass/*.bam"
		File pass_fastq = "${OUTPUT_PATH}/pass/*.fastq"

		File fail_bam = "${OUTPUT_PATH}/fail/*.bam"
		File fail_fastq = "${OUTPUT_PATH}/fail/*.fastq"

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