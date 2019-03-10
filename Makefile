STILL_Y4M = $(wildcard ref/still/*.y4m)
STILL_Y4M_32 = $(patsubst ref/still/%.y4m,ref/still-32/%.y4m,$(STILL_Y4M))
STILL_JPG = $(patsubst ref/still-32/%.y4m,dis/still/%.jpg,$(STILL_Y4M_32))
STILL_IVF = $(patsubst ref/still-32/%.y4m,dis/still/%.ivf,$(STILL_Y4M_32))
STILL_WEBM = $(patsubst ref/still-32/%.y4m,dis/still/%.webm,$(STILL_Y4M_32))
TIME_LOG = dis/still/time.csv
.PRECIOUS: $(STILL_Y4M_32)

VMAF_PATH ?= ../vmaf
IM_QUALITY=18
SVTAV1_ENC_MODE=0
SVTAV1_QP=52
LIBAOM_CPU_USED=0
LIBAOM_CQ_LEVEL=35

all: still

ref/still-32/%.y4m: ref/still/%.y4m
	ffmpeg -v error -i "$^" -vf "crop=floor(iw/32)*32:floor(ih/32)*32:0:0" -y "$@"

dis/still/%.jpg: ref/still-32/%.y4m
	ffmpeg -v error -i "$^" \
			-vf scale=in_color_matrix=bt709:out_color_matrix=bt601:out_range=jpeg \
			-sws_flags lanczos+accurate_rnd+bitexact+full_chroma_int+full_chroma_inp \
			-pix_fmt uyvy422 -f rawvideo - |\
	time -f "$(notdir $@)|%e" convert \
		-size $(shell ffprobe -v quiet -show_entries frame=width,height -of csv=s=x:p=0 "$^") \
		UYVY:- -sampling-factor 4:2:0 -quality $(IM_QUALITY) -strip "$@" \
		2>>$(TIME_LOG)

dis/still/%.ivf: ref/still-32/%.y4m
	time -f "$(notdir $@)|%e" SvtAv1EncApp -i "$^" -b "$@" \
		-enc-mode $(SVTAV1_ENC_MODE) -rc 0 -q $(SVTAV1_QP) \
		2>>$(TIME_LOG) >/dev/null

dis/still/%.webm: ref/still-32/%.y4m
	time -f "$(notdir $@)|%e" aomenc "$^" -o "$@" -q \
		--cpu-used=$(LIBAOM_CPU_USED) \
		--end-usage=q --cq-level=$(LIBAOM_CQ_LEVEL) \
		--threads=8 --row-mt=1 --tile-columns=1 --tile-rows=1 --frame-parallel=0 \
		2>>$(TIME_LOG)

ref:
	mkdir -p ref/still
	wget -qO- https://media.xiph.org/video/derf/subset1-y4m.tar.gz |\
		tar -C ref/still --strip-components=1 -xzvf -

.venv:
	virtualenv .venv -p python2
	.venv/bin/pip install numpy scipy matplotlib pandas scikit-learn scikit-image h5py sureal

prepare: ref .venv
	mkdir -p ref/still-32 dis/still
	[ -f $(TIME_LOG) ] || echo "filename|elapsed" > $(TIME_LOG)

graph:
	PYTHONPATH=$(VMAF_PATH)/python/src ./graph.py \
		"-enc-mode $(SVTAV1_ENC_MODE) -qp $(SVTAV1_QP) vs -cpu-used $(LIBAOM_CPU_USED) -cq-level $(LIBAOM_CQ_LEVEL)"

still: prepare $(STILL_JPG) $(STILL_IVF) $(STILL_WEBM) graph

clean:
	rm -rf ref/still-32 dis/still

distclean:
	rm -rf ref dis .venv