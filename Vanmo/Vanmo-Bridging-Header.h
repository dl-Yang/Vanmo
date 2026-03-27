#ifndef Vanmo_Bridging_Header_h
#define Vanmo_Bridging_Header_h

// FFmpeg headers for MKV demuxing and decoding.
// To enable: add FFMPEG_ENABLED=1 to GCC_PREPROCESSOR_DEFINITIONS
// and -DFFMPEG_ENABLED to OTHER_SWIFT_FLAGS in project.yml,
// then place FFmpeg static libs in Vanmo/Frameworks/FFmpeg/

#ifdef FFMPEG_ENABLED
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_videotoolbox.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/samplefmt.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#endif

#endif /* Vanmo_Bridging_Header_h */
