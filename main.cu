#include <stdio.h>
#include <cuda_runtime.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>


#define TEST_LEN_LINIT 20
#define CHARSET_LEN_LIMIT 100

#define CONST_CHARSET "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_!?"
#define CONST_CHARSET_LENGTH (sizeof(CONST_CHARSET) - 1)

#define CONST_WORD_LENGTH_MIN 1
#define CONST_WORD_LENGTH_MAX 8

#define TOTAL_BLOCKS 65535UL
//#define TOTAL_BLOCKS 32768UL
#define TOTAL_THREADS 512UL
#define HASHES_PER_KERNEL 128UL

#include "md5.cu"


uint8_t word_length;

char word[TEST_LEN_LINIT];
char charset[CHARSET_LEN_LIMIT];
char cracked[TEST_LEN_LINIT];

__device__ char device_charset[CHARSET_LEN_LIMIT];
__device__ char devicecracked[TEST_LEN_LINIT];

__device__ int get_next_dev(uint8_t* length, char* word, uint64_t increment){
    uint64_t idx = 0;
    uint64_t add = 0;
  
    while(increment > 0 && idx < TEST_LEN_LINIT)
    {
        if(idx >= *length && increment > 0)
        {
              increment--;
        }
    
    add = increment + word[idx];
    word[idx] = add % CONST_CHARSET_LENGTH;
    increment = add / CONST_CHARSET_LENGTH;
    idx++;
    }
  
    if(idx > *length)
    {
        *length = idx;
    }
  
    if(idx > CONST_WORD_LENGTH_MAX)
    {
        return 0;
    }

    return 1;
}

int get_next(uint8_t* length, char* word, uint64_t increment){
    uint64_t idx = 0;
    uint64_t add = 0;
  
    while(increment > 0 && idx < TEST_LEN_LINIT)
    {
        if(idx >= *length && increment > 0)
        {
              increment--;
        }
    
    add = increment + word[idx];
    word[idx] = add % CONST_CHARSET_LENGTH;
    increment = add / CONST_CHARSET_LENGTH;
    idx++;
    }
  
    if(idx > *length)
    {
        *length = idx;
    }
  
    if(idx > CONST_WORD_LENGTH_MAX)
    {
        return 0;
    }

    return 1;
}


__global__ void md5Crack(uint8_t wordLength, char* charsetWord, uint32_t hash01, uint32_t hash02, uint32_t hash03, uint32_t hash04){
  //uint64_t idx = ((gridDim.x * blockIdx.y + blockIdx.x )* blockDim.x + threadIdx.x) * HASHES_PER_KERNEL;
  uint64_t idx = (blockIdx.x * blockDim.x + threadIdx.x) * HASHES_PER_KERNEL;
  
  /* Shared variables */
  __shared__ char sharedCharset[CHARSET_LEN_LIMIT];
  
  /* Thread variables */
  char threadCharsetWord[TEST_LEN_LINIT];
  char threadTextWord[TEST_LEN_LINIT];
  uint8_t threadWordLength;
  uint32_t threadHash01, threadHash02, threadHash03, threadHash04;
  
  /* Copy everything to local memory */
  memcpy(threadCharsetWord, charsetWord, TEST_LEN_LINIT);
  memcpy(&threadWordLength, &wordLength, sizeof(uint8_t));
  memcpy(sharedCharset, device_charset, sizeof(uint8_t) * CHARSET_LEN_LIMIT);
  
  /* Increment current word by thread index */
  get_next_dev(&threadWordLength, threadCharsetWord, idx);
  
  for(uint32_t hash = 0; hash < HASHES_PER_KERNEL; hash++){
    for(uint32_t i = 0; i < threadWordLength; i++){
      threadTextWord[i] = sharedCharset[threadCharsetWord[i]];
    }
    
    md5Hash((unsigned char*)threadTextWord, threadWordLength, &threadHash01, &threadHash02, &threadHash03, &threadHash04);   

    if(threadHash01 == hash01 && threadHash02 == hash02 && threadHash03 == hash03 && threadHash04 == hash04){
      memcpy(devicecracked, threadTextWord, threadWordLength);
    }
    
    if(!get_next_dev(&threadWordLength, threadCharsetWord, 1)){
      break;
    }
  }
}



int main(int argc ,char *argv[])
{
    int opt = 0;   
    uint32_t md5Hash[4];
    /* Amount of available devices */
    int devices;
    cudaGetDeviceCount(&devices);
  
    /* Sync type */
    cudaSetDeviceFlags(cudaDeviceScheduleSpin);
  
    /* Display amount of devices */
    printf("Notice: %d device(s) found\n",devices);
    while ((opt = getopt(argc, argv, "mht:f:")) != -1) {
        switch (opt) {
        case 'h':
            printf("input---> %s\n",argv[2]);
    // Get input md5 hex
            for(uint8_t i = 0; i < 4; i++)
            {
                char tmp[16];
    
                strncpy(tmp, argv[2] + i * 8, 8);
                sscanf(tmp, "%x", &md5Hash[i]);   
                md5Hash[i] = (md5Hash[i] & 0xFF000000) >> 24 | (md5Hash[i] & 0x00FF0000) >> 8 | (md5Hash[i] & 0x0000FF00) << 8 | (md5Hash[i] & 0x000000FF) << 24;
            }
            break;
        default:
            printf("Use -h to input hex of MD5 hash\n");
            exit(EXIT_FAILURE);
        }
    }
    //
    if(argc == 1)
    {
        printf("Use -h to input hex of MD5 hash\n");
        exit(EXIT_FAILURE);
    }
    // set default value
    for(uint8_t i = 0; i < TEST_LEN_LINIT; i++)
    {
        word[i] = 0;
        cracked[i] = 0;
    }
    for(uint8_t i = 0; i < CONST_CHARSET_LENGTH; i++)
    {
        charset[i] = CONST_CHARSET[i];
    }
    word_length = CONST_WORD_LENGTH_MIN;
    
    cudaSetDevice(0);
    
    char **words;
    words = (char**)malloc(sizeof(char*) * devices);
    
    cudaSetDeviceFlags(cudaDeviceScheduleYield);
    /* Time */
    cudaEvent_t clockBegin;
    cudaEvent_t clockLast;

    cudaEventCreate(&clockBegin);
    cudaEventCreate(&clockLast);
    cudaEventRecord(clockBegin, 0);

    for(int device = 0; device < devices; device++)
    {
        cudaSetDevice(device);
    
    /* Copy to each device */
        cudaMemcpyToSymbol(device_charset, charset, sizeof(uint8_t) * CHARSET_LEN_LIMIT, 0, cudaMemcpyHostToDevice);
        cudaMemcpyToSymbol(devicecracked, cracked, sizeof(uint8_t) * TEST_LEN_LINIT, 0, cudaMemcpyHostToDevice);
    
    /* Allocate on each device */
        cudaMalloc((void**)&words[device], sizeof(uint8_t) * TEST_LEN_LINIT);
    }
    while(true)
    {
        int result = 0;
        int found = 0;
        for(int device = 0; device < devices; device++)
        {
            cudaSetDevice(device);
            cudaMemcpy(words[device], word, sizeof(uint8_t) * TEST_LEN_LINIT, cudaMemcpyHostToDevice);
            // Kernel function
            md5Crack<<<TOTAL_BLOCKS , TOTAL_THREADS>>>(word_length, words[device], md5Hash[0], md5Hash[1], md5Hash[2], md5Hash[3]);
            result = get_next(&word_length, word, TOTAL_THREADS * HASHES_PER_KERNEL * TOTAL_BLOCKS);
            
        }
        char now[TEST_LEN_LINIT];
        for(int i = 0 ; i < word_length ; i++)
        {
            now[i] = charset[word[i]];
        }
        printf("Now testing :");
        for(int i = 0; i < word_length; i++)
        {
            printf("%c",now[i]);        
        }
        printf("(%d)\n",word_length);
        
        for(int device = 0; device < devices; device++){
            cudaSetDevice(device);

            /* Synchronize now */
            cudaDeviceSynchronize();

            /* Copy result */
            cudaMemcpyFromSymbol(cracked, devicecracked, sizeof(uint8_t) * TEST_LEN_LINIT, 0, cudaMemcpyDeviceToHost); 

            /* Check result */
            if(found = *cracked != 0)
            {     
                    printf("Notice: cracked %s\n",cracked);
                    break;
            }
        }
        
        if(!result || found){
            if(!result && !found){
                    printf("Notice: found nothing (host)");
            }

            break;
        }

    }    
    for(int device = 0; device < devices; device++){
        cudaSetDevice(device);

        /* Free on each device */
        cudaFree((void**)words[device]);
    }
    /* Free array */
    free(words);

    /* Main device */
    cudaSetDevice(0);

    float milliseconds = 0;

    cudaEventRecord(clockLast, 0);
    cudaEventSynchronize(clockLast);
    cudaEventElapsedTime(&milliseconds, clockBegin, clockLast);

    printf("Notice: computation time %f ms\n",milliseconds);

    cudaEventDestroy(clockBegin);
    cudaEventDestroy(clockLast);
    
    return 0;
}

