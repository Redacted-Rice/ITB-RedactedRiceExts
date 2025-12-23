#ifndef SCANNER_BASIC_AVX2_H
#define SCANNER_BASIC_AVX2_H

#include "scanner_basic.h"

// AVX2-optimized scanner for basic types (INT, FLOAT, DOUBLE, BYTE, BOOL)
// Uses SIMD instructions for parallel comparison (4-8x faster than scalar)
// Falls back to BasicScanner if AVX2 is not available at runtime
class BasicScannerAVX2 : public BasicScanner {
public:
	BasicScannerAVX2(DataType dataType, size_t maxResults, size_t alignment);
	virtual ~BasicScannerAVX2();

	// Check if AVX2 is supported on this CPU
	static bool isAVX2Supported();

protected:
	// Override chunk scanning with AVX2 SIMD optimizations
	virtual void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                               ScanType scanType, const void* targetValue,
	                               std::vector<ScanResult>& localResults, size_t maxLocalResults) override;

private:
	// Common helper for aligned offset calculation
	size_t findAlignedOffset(uintptr_t chunkBase) const;

	// Helper to get comparison mask for current chunk
	// Returns mask of matching elements based on scan type
	int getComparisonMask(const uint8_t* buffer, ScanType scanType, const void* targetValue);
	
	// Helper to extract match from mask based on data type
	bool isMatchInMask(int mask, size_t valueIndex, DataType type) const;
};

#endif
