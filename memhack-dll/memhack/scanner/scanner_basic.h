#ifndef SCANNER_BASIC_H
#define SCANNER_BASIC_H

#include "scanner_base.h"
#include <windows.h>

// Scanner implementation for basic types (INT, FLOAT, DOUBLE, BYTE, BOOL)
// Uses basic alignment-based scanning for universal support
class BasicScanner : public Scanner {
public:
	BasicScanner(DataType dataType, size_t maxResults, size_t alignment);
	virtual ~BasicScanner();

protected:
	// Chunk scanning - basic scanner implements alignment-based scan
	virtual void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                               ScanType scanType, const void* targetValue) override;

	// Rescan pure virtuals - basic scanner implementations
	virtual bool validateValueDirect(uintptr_t address, uintptr_t regionEnd,
	                                  ScanType scanType, const void* targetValue,
	                                  ScanResult& outResult) const override;
	virtual bool validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                                    uintptr_t actualAddress, ScanType scanType, const void* targetValue,
	                                    ScanResult& outResult) const override;

	// pure virtual getters implementations
	virtual size_t getDataTypeSize() const override;
	virtual bool isSequenceType() const override { return false; }

private:
	// Compare values (int, float, etc)
	bool compare(const void* a, const void* b) const;
	bool compareGreater(const void* a, const void* b) const;
	bool compareLess(const void* a, const void* b) const;

	// Check if value matches scan criteria
	bool checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const;

	// Read value from buffer at offset
	bool readValueFromBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                         ScanResult& result, uintptr_t actualAddress) const;

	// Read value directly from memory for rescans
	bool readValueDirect(uintptr_t address, uintptr_t regionEnd, ScanResult& result) const;
};

#endif
