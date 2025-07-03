#ifndef  RECORDER_H
#define  RECORDER_H

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdatomic.h>


typedef struct {
    atomic_uint writeIdx , readIdx;
    uint32_t BufferCapacity;
    uint8_t data[];
} audioBuffer;

typedef struct{
    int creator;
    int fd;
    audioBuffer* buffer;
    uint32_t samplerate;
    uint8_t channels;
    uint8_t bits_per_sample ;
    char shm_name[20];
}AudioRecorder;


AudioRecorder* Initialization (const char* name, uint32_t samplerate, uint8_t channels, uint8_t bps, uint16_t seconds_to_store);
void Record(AudioRecorder* recorder , void *source, size_t size);
int Save(AudioRecorder* recorder, const char* filepath , uint16_t seconds_to_save);
void Stop(AudioRecorder* recorder);

#endif
