#define _POSIX_C_SOURCE 200809L
#include "recorder.h"
#include <stddef.h>
#include <stdint.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>


AudioRecorder* Initialization (const char* name, uint32_t samplerate, uint8_t channels, uint8_t bps, uint16_t seconds_to_store){
    size_t bytes_per_sec = samplerate * channels * bps / 8;
    size_t bytes_to_store = bytes_per_sec * seconds_to_store;
    size_t size = sizeof(audioBuffer) + bytes_to_store;

    shm_unlink(name);
    int fd = shm_open(name,  O_CREAT | O_RDWR , 0666);
    if( fd == -1 || ftruncate(fd , size)) {
        perror("error in opening or truncating");
        return NULL;
    }
    void *mapped_memory_pointer = mmap(NULL , size , PROT_READ | PROT_WRITE , MAP_SHARED , fd , 0);
    if(mapped_memory_pointer == MAP_FAILED) {
        perror("error in mapping memory");
        close(fd);
        return NULL;
    }
    audioBuffer* buffer = (audioBuffer*) mapped_memory_pointer;
    buffer->BufferCapacity = bytes_to_store;
    atomic_store(&buffer->writeIdx ,0);
    atomic_store(&buffer->readIdx ,0);
    
    AudioRecorder* recorder = (AudioRecorder*) malloc(sizeof(*recorder));
    if (!recorder) {
        munmap(mapped_memory_pointer , size);
        close(fd);
        return NULL;
    }
   *recorder = (AudioRecorder){ 
        .creator = 1, 
        .fd = fd, 
        .buffer = buffer, 
        .samplerate = samplerate, 
        .channels = channels, 
        .bits_per_sample = bps
    };
    strncpy(recorder->shm_name, name, sizeof(recorder->shm_name) - 1);
    recorder->shm_name[sizeof(recorder->shm_name) - 1] = '\0';
    return recorder;
}


void Record(AudioRecorder* recorder , void *source, size_t size) {
    
    audioBuffer* buffer = recorder->buffer;
    size_t writeIdx = atomic_load_explicit(&buffer->writeIdx, memory_order_acquire);
    size_t readIdx = atomic_load_explicit(&buffer->readIdx, memory_order_acquire);
    size_t capacity = buffer->BufferCapacity;

    size_t free = (readIdx <= writeIdx) ? (capacity - writeIdx + readIdx -1) : (readIdx - writeIdx -1);
    if (free < size) {
        size_t drop = size-free ;
        readIdx = (readIdx + drop) % capacity ;
        atomic_store_explicit(&buffer->readIdx, readIdx, memory_order_release);
    }
    
    size_t head = writeIdx ;
    size_t first = (size <= capacity - head) ? size : capacity - head ;
    memcpy(buffer->data + head, source , first );
    if (size > first) {
        memcpy(buffer->data, (uint8_t *)source + first, size - first);
    }
    atomic_store_explicit(&buffer->writeIdx, (writeIdx + size) % capacity, memory_order_release);

}



static int write_wav(const char *path, const uint8_t *pcm, size_t n,
                     uint32_t sr, uint16_t ch, uint16_t bps){
    struct __attribute__((packed)) {
        char riff[4]; uint32_t cs; char wave[4];
        char fmt_[4]; uint32_t fl; uint16_t af, ch; uint32_t sr;
        uint32_t br; uint16_t ba; uint16_t bps; char data[4]; uint32_t ds;
    } h = { "RIFF", 36 + (uint32_t)n, "WAVE",
            "fmt ", 16, (bps == 32 ? 3 : 1), ch, sr,
            sr * ch * (bps/8), ch * (bps/8), bps, "data", (uint32_t)n };
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    fwrite(&h, sizeof h, 1, f);
    fwrite(pcm, 1, n, f);
    fclose(f);
    
    return 0;
}

int Save(AudioRecorder* recorder, const char* filepath , uint16_t seconds_to_save){
    audioBuffer* buffer = recorder->buffer;
    uint32_t capacity = buffer->BufferCapacity;
    uint32_t write = atomic_load_explicit(&buffer->writeIdx,memory_order_acquire);
    uint32_t read = atomic_load_explicit(&buffer->readIdx,memory_order_acquire);


    size_t available = (write >= read) ? (write - read) : (capacity + write - read);
    size_t need = (size_t)recorder->samplerate * (size_t)recorder->channels * ((size_t)recorder->bits_per_sample/8) * (size_t)seconds_to_save;
    size_t want = (need < available) ? need : available;
    if (want == 0) return -1;
     uint8_t *buf = malloc(want);
    if (!buf) return -1;
    
    if (want <= write) {
        memcpy(buf, buffer->data + (write - want), want);
    } else {
        size_t first = want - write;
        size_t second = write;
        memcpy(buf, buffer->data + (capacity - first), first);
        memcpy(buf + first, buffer->data, second);
    }
    int result = write_wav(filepath, buf, want, recorder->samplerate, 
                          recorder->channels, recorder->bits_per_sample);
    free(buf);
    
    return result;
}

void Stop(AudioRecorder* recorder){
     if(!recorder) return;
     size_t total = sizeof(audioBuffer) + recorder->buffer->BufferCapacity;
     if(recorder->creator){
        shm_unlink(recorder->shm_name);
     }
     close(recorder->fd );
     free(recorder);
}