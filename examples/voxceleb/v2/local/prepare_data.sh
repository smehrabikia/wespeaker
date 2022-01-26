#!/bin/bash
# coding:utf-8
# Author: Hongji Wang
# Created on: 20220123

stage=-1
stop_stage=-1

. tools/parse_options.sh || exit 1;

download_dir=data/download_data
rawdata_dir=data/raw_data


if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    echo "Download musan.tar.gz, rirs_noises.zip, vox1_test_wav.zip, vox1_dev_wav.zip, and vox2_aac.zip."
    echo "This may take a long time. Thus we recommand you to download all archives above in your own way first."
    
    ./local/download_data.sh --download_dir ${download_dir}
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    echo "Decompress all archives ..."
    echo "This could take some time ..."
    
    for archive in musan.tar.gz rirs_noises.zip vox1_test_wav.zip vox1_dev_wav.zip vox2_aac.zip ; do
        [ ! -f ${download_dir}/$archive ] && echo "Archive $archive not exists !!!" && exit 1;
    done
    [ ! -d ${rawdata_dir} ] && mkdir -p ${rawdata_dir}
    
    if [ ! -d ${rawdata_dir}/musan ]; then
        tar -xzvf ${download_dir}/musan.tar.gz -C ${rawdata_dir}
    fi

    if [ ! -d ${rawdata_dir}/RIRS_NOISES ]; then
        unzip ${download_dir}/rirs_noises.zip -d ${rawdata_dir}
    fi

    if [ ! -d ${rawdata_dir}/voxceleb1 ]; then
        mkdir -p ${rawdata_dir}/voxceleb1/test ${rawdata_dir}/voxceleb1/dev
        unzip ${download_dir}/vox1_test_wav.zip -d ${rawdata_dir}/voxceleb1/test
        unzip ${download_dir}/vox1_dev_wav.zip -d ${rawdata_dir}/voxceleb1/dev
    fi
    
    if [ ! -d ${rawdata_dir}/voxceleb2_m4a ]; then
        mkdir -p ${rawdata_dir}/voxceleb2_m4a
        unzip ${download_dir}/vox2_aac.zip -d ${rawdata_dir}/voxceleb2_m4a
    fi

    echo "Decompress success !!!"
fi

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    echo "Convert voxceleb2 wav format from m4a to wav using ffmpeg."
    echo "This could also take some time ..."
    
    if [ ! -d ${rawdata_dir}/voxceleb2_wav ]; then
        ./local/m4a2wav.pl ${rawdata_dir}/voxceleb2_m4a dev ${rawdata_dir}/voxceleb2_wav
        # split m4a2wav_dev.sh into sub_file, then we can use multi progresses
        data_num=`wc -l ${rawdata_dir}/voxceleb2_wav/dev/m4a2wav_dev.sh | awk '{print $1}'`
        nj=8 # num of jobs
        subfile_num=$[$data_num/$nj+1]
        split -l ${subfile_num} -d -a 3 ${rawdata_dir}/voxceleb2_wav/dev/m4a2wav_dev.sh ${rawdata_dir}/voxceleb2_wav/dev/split_
        for suffix in `seq 0 $[$nj-1]`; do
            suffix=`printf '%03d' $suffix`
            sh ${rawdata_dir}/voxceleb2_wav/dev/split_${suffix} &
        done
        wait
    fi
    
    echo "Convert m4a2wav success !!!"
fi

if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ]; then
    echo "Prepare wav.scp for each dataset ..."
    
    mkdir -p data/musan data/rirs_noises data/vox1 data/vox2_dev
    # musan
    find `pwd`/${rawdata_dir}/musan -name "*.wav" | awk -F"/" '{print $(NF-2)"/"$(NF-1)"/"$NF,$0}' > data/musan/wav.scp
    # rirs_noises
    find `pwd`/${rawdata_dir}/RIRS_NOISES/simulated_rirs -name "*.wav" | awk -F"/" '{print $(NF-2)"/"$(NF-1)"/"$NF,$0}' > data/rirs_noises/wav.scp
    # vox1
    find `pwd`/${rawdata_dir}/voxceleb1 -name "*.wav" | awk -F"/" '{print $(NF-2)"/"$(NF-1)"/"$NF,$0}' | sort > data/vox1/wav.scp
    awk '{print $1}' data/vox1/wav.scp | awk -F "/" '{print $0,$1}' > data/vox1/utt2spk
    ./tools/utt2spk_to_spk2utt.pl data/vox1/utt2spk > data/vox1/spk2utt
    if [ ! -d data/vox1/trials ]; then
        echo "Download trials for vox1 ..."
        mkdir -p data/vox1/trials
        #wget --no-check-certificate https://www.robots.ox.ac.uk/~vgg/data/voxceleb/meta/veri_test.txt -O data/vox1/trials/vox1-O.txt
        #wget --no-check-certificate https://www.robots.ox.ac.uk/~vgg/data/voxceleb/meta/list_test_hard.txt -O data/vox1/trials/vox1-H.txt
        #wget --no-check-certificate https://www.robots.ox.ac.uk/~vgg/data/voxceleb/meta/list_test_all.txt -O data/vox1/trials/vox1-E.txt
        wget --no-check-certificate https://www.robots.ox.ac.uk/~vgg/data/voxceleb/meta/veri_test2.txt -O data/vox1/trials/vox1-O\(cleaned\).txt
        wget --no-check-certificate https://www.robots.ox.ac.uk/~vgg/data/voxceleb/meta/list_test_hard2.txt -O data/vox1/trials/vox1-H\(cleaned\).txt
        wget --no-check-certificate https://www.robots.ox.ac.uk/~vgg/data/voxceleb/meta/list_test_all2.txt -O data/vox1/trials/vox1-E\(cleaned\).txt
        # transform them into kaldi trial format
        awk '{if($1==0)label="nontarget";else{label="target"}; print $2,$3,label}' data/vox1/trials/vox1-O\(cleaned\).txt > data/vox1/trials/vox1_O_cleaned.kaldi
        awk '{if($1==0)label="nontarget";else{label="target"}; print $2,$3,label}' data/vox1/trials/vox1-H\(cleaned\).txt > data/vox1/trials/vox1_H_cleaned.kaldi
        awk '{if($1==0)label="nontarget";else{label="target"}; print $2,$3,label}' data/vox1/trials/vox1-E\(cleaned\).txt > data/vox1/trials/vox1_E_cleaned.kaldi
    fi
    # vox2
    find `pwd`/${rawdata_dir}/voxceleb2_wav -name "*.wav" | awk -F"/" '{print $(NF-2)"/"$(NF-1)"/"$NF,$0}' | sort > data/vox2_dev/wav.scp
    awk '{print $1}' data/vox2_dev/wav.scp | awk -F "/" '{print $0,$1}' > data/vox2_dev/utt2spk
    ./tools/utt2spk_to_spk2utt.pl data/vox2_dev/utt2spk > data/vox2_dev/spk2utt

    echo "Success !!! Now data preparation is done !!!"
fi
