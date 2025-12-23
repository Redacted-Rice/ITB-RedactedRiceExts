#include "stdafx.h"
#include "scanner_basic_avx2.h"
#include <immintrin.h>  // AVX2 intrinsics
#include <intrin.h>     // __cpuid

BasicScannerAVX2::BasicScannerAVX2(DataType dataType, size_t maxResults, size_t alignment)
	: BasicScanner(dataType, maxResults, alignment) {
	// Nothing else needed
}

BasicScannerAVX2::~BasicScannerAVX2() {}

// Check if AVX2 is supported on this CPU
bool BasicScannerAVX2::isAVX2Supported() {
	int cpuInfo[4];

	// CPUID function 0: Get maximum supported function number
	__cpuid(cpuInfo, 0);
	int maxFunctionId = cpuInfo[0];

	// AVX2 requires CPUID function 7
	if (maxFunctionId < 7) {
		return false;
	}

	// CPUID function 7, sub-leaf 0: Get extended features
	__cpuidex(cpuInfo, 7, 0);

	// EBX register, bit 5 = AVX2 support
	const int AVX2_BIT = 5;
	return (cpuInfo[1] & (1 << AVX2_BIT)) != 0;
}

// Find aligned starting offset
size_t BasicScannerAVX2::findAlignedOffset(uintptr_t chunkBase) const {
	uintptr_t firstAlignedAddr = chunkBase;
	if (firstAlignedAddr % alignment != 0) {
		firstAlignedAddr += alignment - (firstAlignedAddr % alignment);
	}
	return (firstAlignedAddr >= chunkBase) ? (firstAlignedAddr - chunkBase) : 0;
}

// Get comparison mask for current chunk
// Performs SIMD comparison and returns mask based on scan type
// NOT scans invert the mask at SIMD level
int BasicScannerAVX2::getComparisonMask(const uint8_t* buffer, ScanType scanType, const void* targetValue) {
	int mask = 0;
	bool invertMask = (scanType == ScanType::NOT);

	switch (dataType) {
		case DataType::INT: {
			int32_t target = *(const int32_t*)targetValue;
			__m256i targetVec = _mm256_set1_epi32(target);
			__m256i dataVec = _mm256_loadu_si256((const __m256i*)buffer);
			__m256i cmpVec = _mm256_cmpeq_epi32(dataVec, targetVec);
			if (invertMask) {
				cmpVec = _mm256_xor_si256(cmpVec, _mm256_set1_epi32(-1));
			}
			mask = _mm256_movemask_epi8(cmpVec);
			break;
		}
		case DataType::FLOAT: {
			float target = *(const float*)targetValue;
			__m256 targetVec = _mm256_set1_ps(target);
			__m256 dataVec = _mm256_loadu_ps((const float*)buffer);
			__m256 cmpVec = _mm256_cmp_ps(dataVec, targetVec, _CMP_EQ_OQ);
			if (invertMask) {
				__m256i cmpInt = _mm256_castps_si256(cmpVec);
				__m256i notInt = _mm256_xor_si256(cmpInt, _mm256_set1_epi32(-1));
				cmpVec = _mm256_castsi256_ps(notInt);
			}
			mask = _mm256_movemask_ps(cmpVec);
			break;
		}
		case DataType::DOUBLE: {
			double target = *(const double*)targetValue;
			__m256d targetVec = _mm256_set1_pd(target);
			__m256d dataVec = _mm256_loadu_pd((const double*)buffer);
			__m256d cmpVec = _mm256_cmp_pd(dataVec, targetVec, _CMP_EQ_OQ);
			if (invertMask) {
				__m256i cmpInt = _mm256_castpd_si256(cmpVec);
				__m256i notInt = _mm256_xor_si256(cmpInt, _mm256_set1_epi32(-1));
				cmpVec = _mm256_castsi256_pd(notInt);
			}
			mask = _mm256_movemask_pd(cmpVec);
			break;
		}
		case DataType::BYTE:
		case DataType::BOOL: {
			uint8_t target = *(const uint8_t*)targetValue;
			__m256i targetVec = _mm256_set1_epi8((char)target);
			__m256i dataVec = _mm256_loadu_si256((const __m256i*)buffer);
			__m256i cmpVec = _mm256_cmpeq_epi8(dataVec, targetVec);
			if (invertMask) {
				cmpVec = _mm256_xor_si256(cmpVec, _mm256_set1_epi32(-1));
			}
			mask = _mm256_movemask_epi8(cmpVec);
			break;
		}
		default:
			break;
	}

	return mask;
}

// Helper to check if a specific value in the mask matched
// Mask interpretation varies by data type:
// - INT/FLOAT: 4 bits per value (32 bits total for 8 values)
// - DOUBLE: 1 bit per value (4 bits total for 4 values)
// - BYTE/BOOL: 1 bit per value (32 bits total for 32 values)
bool BasicScannerAVX2::isMatchInMask(int mask, size_t valueIndex, DataType type) const {
	switch (type) {
		case DataType::INT:
		case DataType::FLOAT:
			// 4 bits per value (each int/float is 4 bytes)
			// All 4 bits must be set for a match
			return ((mask >> (valueIndex * 4)) & 0xF) == 0xF;

		case DataType::DOUBLE:
			// 1 bit per value
			return (mask & (1 << valueIndex)) != 0;

		case DataType::BYTE:
		case DataType::BOOL:
			// 1 bit per value
			return (mask & (1 << valueIndex)) != 0;

		default:
			return false;
	}
}

// Override chunk scanning with AVX2 dispatcher - scans into local results
void BasicScannerAVX2::scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
                                          ScanType scanType, const void* targetValue,
                                          std::vector<ScanResult>& localResults, size_t maxLocalResults) {
	// Use scalar path for non-EXACT/NOT scans
	if (scanType != ScanType::EXACT && scanType != ScanType::NOT) {
		BasicScanner::scanChunkInRegion(buffer, chunkSize, chunkBase, scanType, targetValue,
		                                localResults, maxLocalResults);
		return;
	}
	
	const size_t avx2_stride = 32;
	const size_t dataSize = getDataTypeSize();
	size_t offset = findAlignedOffset(chunkBase);
	
	// AVX2 processing
	while (offset + avx2_stride <= chunkSize && localResults.size() < maxLocalResults) {
		int mask = getComparisonMask(buffer + offset, scanType, targetValue);
		
		if (mask != 0) {
			size_t valuesPerChunk = avx2_stride / dataSize;
			
			for (size_t i = 0; i < valuesPerChunk; i++) {
				size_t pos = offset + i * dataSize;
				if (pos + dataSize <= chunkSize) {
					if (isMatchInMask(mask, i, dataType)) {
						uintptr_t actualAddress = chunkBase + pos;
						ScanResult result;
						if (readValueFromBuffer(buffer, chunkSize, pos, result, actualAddress)) {
							localResults.push_back(result);
							
							if (localResults.size() >= maxLocalResults) {
								return;
							}
						}
					}
				}
			}
		}
		
		offset += avx2_stride;
	}
	
	// Scalar remainder
	while (offset + dataSize <= chunkSize && localResults.size() < maxLocalResults) {
		uintptr_t actualAddress = chunkBase + offset;
		
		if (actualAddress % alignment == 0) {
			ScanResult result;
			if (validateValueInBuffer(buffer, chunkSize, offset, actualAddress, scanType, targetValue, result)) {
				localResults.push_back(result);
			}
		}
		
		offset += alignment;
	}
}
