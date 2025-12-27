#ifndef SCANNER_BASIC_H
#define SCANNER_BASIC_H

#include "scanner_base.h"
#include <windows.h>

// Scanner implementation for basic types (INT, FLOAT, DOUBLE, BYTE, BOOL)
// Uses basic alignment-based scanning for universal support
class BasicScanner : public Scanner {
public:
    // Data types
    enum class DataType {
    	BYTE,
    	INT,
    	FLOAT,
    	DOUBLE,
    	BOOL
    };

	BasicScanner(DataType dataType, size_t maxResults, size_t alignment);
	virtual ~BasicScanner();
	
	static BasicScanner* create(DataType dataType, size_t maxResults, size_t alignment);

    static bool compare(const void* a, const void* b, DataType type) const;
    static size_t getDataTypeSize(DataType type) const;

protected:
	// Chunk scanning - scans into local results vector
	virtual void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                               ScanType scanType, const void* targetValue,
	                               std::vector<ScanResult>& localResults, size_t maxLocalResults) override;

	// Rescan pure virtuals - basic scanner implementations
	virtual bool validateValueDirect(uintptr_t address, uintptr_t regionEnd,
	                                  ScanType scanType, const void* targetValue,
	                                  ScanResult& outResult) const override;
	virtual bool validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                                    uintptr_t actualAddress, ScanType scanType, const void* targetValue,
	                                    ScanResult& outResult) const override;

	// pure virtual getters implementations
	virtual size_t getDataTypeSize() const override;

	// Compare values (int, float, etc)
	bool compareGreater(const void* a, const void* b) const;
	bool compareLess(const void* a, const void* b) const;

	// Check if value matches scan criteria
	bool checkMatch(const ScanResult& result, ScanType scanType, const void* targetValue) const;

	// Read value from buffer at offset
	bool readValueFromBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                         ScanResult& result, uintptr_t actualAddress) const;

	// Read value directly from memory for rescans
	bool readValueDirect(uintptr_t address, uintptr_t regionEnd, ScanResult& result) const;
	
	DataType dataType;
};

#endif
