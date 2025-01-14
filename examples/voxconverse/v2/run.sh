#!/bin/bash
# Copyright (c) 2022 Xu Xiang
#               2022 Zhengyang Chen (chenzhengyang117@gmail.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

. ./path.sh || exit 1

stage=-1
stop_stage=-1
sad_type="system"
# do cmn on the sub-segment or on the vad segment
subseg_cmn=true
# whether print the evaluation result for each file
get_each_file_res=1

. tools/parse_options.sh

# Prerequisite
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    mkdir -p external_tools

    # [1] Download evaluation toolkit
    wget -c https://github.com/usnistgov/SCTK/archive/refs/tags/v2.4.12.zip -O external_tools/SCTK-v2.4.12.zip
    unzip -o external_tools/SCTK-v2.4.12.zip -d external_tools

    # [2] Download voice activity detection model pretrained by Silero Team
    wget -c https://github.com/snakers4/silero-vad/archive/refs/tags/v3.1.zip -O external_tools/silero-vad-v3.1.zip
    unzip -o external_tools/silero-vad-v3.1.zip -d external_tools

    # [3] Download ResNet34 speaker model pretrained by WeSpeaker Team
    mkdir -p pretrained_models

    wget -c https://wespeaker-1256283475.cos.ap-shanghai.myqcloud.com/models/voxceleb/voxceleb_resnet34_LM.onnx -O pretrained_models/voxceleb_resnet34_LM.onnx
fi


# Download VoxConverse dev audios and the corresponding annotations
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    mkdir -p data

    # Download annotations for dev and test sets
    wget -c https://github.com/joonson/voxconverse/archive/refs/heads/master.zip -O data/voxconverse_master.zip
    unzip -o data/voxconverse_master.zip -d data

    # Download dev audios
    mkdir -p data/dev
    wget -c https://mm.kaist.ac.kr/datasets/voxconverse/data/voxconverse_dev_wav.zip -O data/voxconverse_dev_wav.zip
    unzip -o data/voxconverse_dev_wav.zip -d data/dev

    # Create wav.scp for dev audios
    ls `pwd`/data/dev/audio/*.wav | awk -F/ '{print substr($NF, 1, length($NF)-4), $0}' > data/dev/wav.scp

    # Test audios
    # mkdir -p data/test
    # wget -c https://mm.kaist.ac.kr/datasets/voxconverse/data/voxconverse_test_wav.zip -O data/voxconverse_test_wav.zip
    # unzip -o data/voxconverse_test_wav.zip -d data/test
fi


# Voice activity detection
if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    # Set VAD min duration
    min_duration=0.255

    if [[ "x${sad_type}" == "xoracle" ]]; then
        # Oracle SAD: handling overlapping or too short regions in ground truth RTTM
        while read -r utt wav_path; do
            python3 sad/make_oracle_sad.py \
                    --rttm data/voxconverse-master/dev/${utt}.rttm \
                    --min-duration $min_duration
        done < data/dev/wav.scp > data/dev/oracle_sad
    fi

    if [[ "x${sad_type}" == "xsystem" ]]; then
       # System SAD: applying 'silero' VAD
       python3 sad/make_system_sad.py \
               --repo-path external_tools/silero-vad-3.1 \
               --scp data/dev/wav.scp \
               --min-duration $min_duration > data/dev/system_sad
    fi
fi


# Extract fbank features
if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ]; then

    [ -d "exp/${sad_type}_sad_fbank" ] && rm -r exp/${sad_type}_sad_fbank

    echo "Make Fbank features and store it under exp/${sad_type}_sad_fbank"
    echo "..."
    bash diar/make_fbank.sh \
            --scp data/dev/wav.scp \
            --segments data/dev/${sad_type}_sad \
            --store_dir exp/${sad_type}_sad_fbank \
            --subseg_cmn ${subseg_cmn} \
            --nj 20
fi

# Extract embeddings
if [ ${stage} -le 5 ] && [ ${stop_stage} -ge 5 ]; then

    [ -d "exp/${sad_type}_sad_embedding" ] && rm -r exp/${sad_type}_sad_embedding

    echo "Extract embeddings and store it under exp/${sad_type}_sad_embedding"
    echo "..."
    bash diar/extract_emb.sh \
            --scp exp/${sad_type}_sad_fbank/fbank.scp \
            --pretrained_model pretrained_models/voxceleb_resnet34_LM.onnx \
            --device cuda \
            --store_dir exp/${sad_type}_sad_embedding \
            --batch_size 96 \
            --frame_shift 10 \
            --window_secs 1.5 \
            --period_secs 0.75 \
            --subseg_cmn ${subseg_cmn} \
            --nj 4
fi


# Applying spectral clustering algorithm
if [ ${stage} -le 6 ] && [ ${stop_stage} -ge 6 ]; then

    [ -f "exp/spectral_cluster/${sad_type}_sad_labels" ] && rm exp/spectral_cluster/${sad_type}_sad_labels

    echo "Doing spectral clustering and store the result in exp/spectral_cluster/${sad_type}_sad_labels"
    echo "..."
    python3 diar/spectral_clusterer.py \
            --scp exp/${sad_type}_sad_embedding/emb.scp \
            --output exp/spectral_cluster/${sad_type}_sad_labels
fi


# Convert labels to RTTMs
if [ ${stage} -le 7 ] && [ ${stop_stage} -ge 7 ]; then
    python3 diar/make_rttm.py \
            --labels exp/spectral_cluster/${sad_type}_sad_labels \
            --channel 1 > exp/spectral_cluster/${sad_type}_sad_rttm
fi


# Evaluate the result
if [ ${stage} -le 8 ] && [ ${stop_stage} -ge 8 ]; then

    echo -e "Get the DER results\n..."
    perl external_tools/SCTK-2.4.12/src/md-eval/md-eval.pl \
         -c 0.25 \
         -r <(cat data/voxconverse-master/dev/*.rttm) \
         -s exp/spectral_cluster/${sad_type}_sad_rttm 2>&1 | tee exp/spectral_cluster/${sad_type}_sad_res

    if [ ${get_each_file_res} -eq 1 ];then
        single_file_res_dir=exp/spectral_cluster/${sad_type}_single_file_res
        mkdir -p $single_file_res_dir
        echo -e "\nGet the DER results for each file and the results will be stored underd ${single_file_res_dir}\n..."

        awk '{print $2}' exp/spectral_cluster/${sad_type}_sad_rttm | sort -u  | while read file_name; do
            perl external_tools/SCTK-2.4.12/src/md-eval/md-eval.pl \
                 -c 0.25 \
                 -r <(cat data/voxconverse-master/dev/${file_name}.rttm) \
                 -s <(grep "${file_name}" exp/spectral_cluster/${sad_type}_sad_rttm) > ${single_file_res_dir}/${file_name}_res
        done
        echo "Done!"
    fi
fi
