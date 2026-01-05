#ifndef SCANNER_SEQUENCE_H
#define SCANNER_SEQUENCE_H

#include "scanner_base.h"
#include <windows.h>

// Maximum size for sequence searches (strings/byte arrays)
// This prevents excessive memory allocation and overlap calculations
// MUST be less than SCAN_BUFFER_SIZE for overlap logic to work correctly
const size_t MAX_SEQUENCE_SIZE = 4096;

// Compile-time assertion to ensure buffer is larger than max sequence
static_assert(SCAN_BUFFER_SIZE > MAX_SEQUENCE_SIZE,
              "SCAN_BUFFER_SIZE must be greater than MAX_SEQUENCE_SIZE for overlap to work");

// Scanner implementation for sequence types (STRING, BYTE_ARRAY)
// Uses memchr-based optimization to quickly find candidate positions
class SequenceScanner : public Scanner {
public:
    // Data types
    enum class DataType {
    	STRING, // Fixed length string. Does not check null term. If needed use byte array for now at least
    	BYTE_ARRAY
    };

	// Override new/delete to allocate from scanner heap
	static void* operator new(size_t size);
	static void operator delete(void* ptr) noexcept;

	SequenceScanner(DataType dataType, size_t maxResults, size_t alignment);
	virtual ~SequenceScanner();

	static SequenceScanner* create(DataType dataType, size_t maxResults, size_t alignment);

	bool readSequenceBytes(uintptr_t address, std::vector<uint8_t, ScannerAllocator<uint8_t>>& outBytes) const;

	const std::vector<uint8_t, ScannerAllocator<uint8_t>>& getSearchSequence() const { return searchSequence; }

	DataType getDataType() const { return dataType; }

	void setSearchSequence(const void* data, size_t size);

	static bool compare(const uint8_t* a, const uint8_t* b, size_t size);

protected:
	// Setup hook - store/update search sequence
	virtual bool setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize) override;

	// only allow EXACT for first scan
	virtual bool validateFirstScanType(ScanType scanType) override;

	// Chunk scanning - sequence scanner implements memchr based scan
	virtual void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                               ScanType scanType, const void* targetValue,
	                               std::vector<ScanResult>& localResults, size_t maxLocalResults) override;

	// Rescan pure virtuals - sequence scanner implementations
	virtual bool validateValueDirect(uintptr_t address, uintptr_t regionStart, uintptr_t regionEnd,
	                                  ScanType scanType, const void* targetValue,
	                                  ScanResult& outResult) const override;
	virtual bool validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                                    uintptr_t actualAddress, ScanType scanType, const void* targetValue,
	                                    ScanResult& outResult) const override;

	// Getters
	virtual size_t getDataTypeSize() const override;
	size_t getSequenceSize() const { return searchSequence.size(); }

	// Sequence specific helpers
	bool checkMatch(const uint8_t* dataToCompare, ScanType scanType) const;
	bool validateSequenceDirect(uintptr_t address, uintptr_t regionEnd, ScanType scanType) const;

	// Sequence storage
	DataType dataType;
	std::vector<uint8_t, ScannerAllocator<uint8_t>> searchSequence;
};

#endif
