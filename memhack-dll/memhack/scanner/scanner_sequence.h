#ifndef SCANNER_SEQUENCE_H
#define SCANNER_SEQUENCE_H

#include "scanner_base.h"
#include <windows.h>

// Scanner implementation for sequence types (STRING, BYTE_ARRAY)
// Uses memchr-based optimization to quickly find candidate positions
class SequenceScanner : public Scanner {
public:
	SequenceScanner(DataType dataType, size_t maxResults, size_t alignment);
	virtual ~SequenceScanner();

	// Sequence specific overrides
	virtual bool readSequenceBytes(uintptr_t address, std::vector<uint8_t, ScannerAllocator<uint8_t>>& outBytes) const override;

protected:
	// Setup hook - store/update search sequence
	virtual bool setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize) override;

	// only allow EXACT for first scan
	virtual bool validateFirstScanType(ScanType scanType) override;

	// Chunk scanning - sequence scanner implements memchr based scan
	virtual void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                               ScanType scanType, const void* targetValue) override;

	// Rescan pure virtuals - sequence scanner implementations
	virtual bool validateValueDirect(uintptr_t address, uintptr_t regionEnd,
	                                  ScanType scanType, const void* targetValue,
	                                  ScanResult& outResult) const override;
	virtual bool validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                                    uintptr_t actualAddress, ScanType scanType, const void* targetValue,
	                                    ScanResult& outResult) const override;

	// Getters
	virtual size_t getDataTypeSize() const override;
	virtual bool isSequenceType() const override { return true; }
	virtual const std::vector<uint8_t, ScannerAllocator<uint8_t>>& getSearchSequence() const override { return searchSequence; }
	virtual size_t getSequenceSize() const override { return searchSequence.size(); }

private:
	// Sequence storage
	std::vector<uint8_t, ScannerAllocator<uint8_t>> searchSequence;

	// Sequence specific helpers
	void setSearchSequence(const void* data, size_t size);
	bool compare(const uint8_t* dataToCompare) const;
	bool checkMatch(const uint8_t* dataToCompare, ScanType scanType) const;
	bool validateSequenceDirect(uintptr_t address, uintptr_t regionEnd, ScanType scanType) const;
};

#endif
