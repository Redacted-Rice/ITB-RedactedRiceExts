#ifndef SCANNER_STRUCT_H
#define SCANNER_STRUCT_H

#include "scanner_base.h"
#include "scanner_basic.h"
#include "scanner_sequence.h"
#include <windows.h>


// Maximum size for struct searches
// This prevents excessive memory allocation and overlap calculations
// MUST be less than SCAN_BUFFER_SIZE for overlap logic to work correctly
const size_t MAX_STRUCT_SIZE = 8192;

// Compile-time assertion to ensure buffer is larger than max struct
static_assert(SCAN_BUFFER_SIZE > MAX_STRUCT_SIZE,
              "SCAN_BUFFER_SIZE must be greater than MAX_STRUCT_SIZE for overlap to work");

// Scanner implementation for struct types
// Uses memchr-based keyed value as base for search
class StructScanner : public Scanner {
public:
	// dont use inheritence so they are easily separated and dont have ti deal with delegation
    class StructFieldBasic {
    public:
        int offsetFromKey;  // Offset from key position (can be negative)
        BasicScanner::DataType type;
        ScanValue val;

		// Override new/delete to allocate from scanner heap
        static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;

    	StructFieldBasic(int offsetFromKey, BasicScanner::DataType type, ScanValue val);
    	~StructFieldBasic() {}

        bool compare(const uint8_t* keyAddr) const;
    };

	// dont use inheritence so they are easily separated and dont have ti deal with delegation
    class StructFieldSequence {
    public:
        int offsetFromKey;  // Offset from key position (can be negative)
        std::vector<uint8_t, ScannerAllocator<uint8_t>> val;

		// Override new/delete to allocate from scanner heap
        static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;

    	StructFieldSequence(int offsetFromKey, const uint8_t* data, size_t size);
    	~StructFieldSequence() {}

        bool compare(const uint8_t* keyAddr) const;
    };

    class StructSearch {
    public:
        uint8_t searchKey;
        std::vector<StructFieldBasic, ScannerAllocator<StructFieldBasic>> basicFields;
        std::vector<StructFieldSequence, ScannerAllocator<StructFieldSequence>> sequenceFields;
		// Offset of the search key from struct base address. Defaults to 0
        int keyOffsetFromBase;
        size_t sizeBeforeKey;
		// Size from key onwards (includes the key byte itself, minimum 1)
        size_t sizeFromKey;

    	// Override new/delete to allocate from scanner heap
    	static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;

    	StructSearch(uint8_t key, int keyOffsetFromBase = 0);
    	~StructSearch() {}

    	void adjustSizes(int offsetFromKey, size_t length) {
    	    // Field spans from key+offset to key+offset+length
    	    if (offsetFromKey < 0) {
    	        // Field starts before the key
    	        size_t bytesBeforeKey = (size_t)(-offsetFromKey);
    	        if (bytesBeforeKey > sizeBeforeKey) {
    	            sizeBeforeKey = bytesBeforeKey;
    	        }
    	        // Check if field goes past the key
    	        int fieldEnd = offsetFromKey + (int)length;
    	        if (fieldEnd > 0) {
    	            if ((size_t)fieldEnd > sizeFromKey) {
    	                sizeFromKey = (size_t)fieldEnd;
    	            }
    	        }
    	    } else {
    	        // Field starts at or after the key
    	        size_t fieldEnd = (size_t)offsetFromKey + length;
    	        if (fieldEnd > sizeFromKey) {
    	            sizeFromKey = fieldEnd;
    	        }
    	    }
    	}

        void addBasicField(int offsetFromBase, BasicScanner::DataType type, ScanValue val) {
            int offsetFromKey = offsetFromBase - keyOffsetFromBase;
            basicFields.emplace_back(offsetFromKey, type, val);
            adjustSizes(offsetFromKey, BasicScanner::getDataTypeSize(type));
        }

        void addSequenceField(int offsetFromBase, const uint8_t* data, size_t size) {
            int offsetFromKey = offsetFromBase - keyOffsetFromBase;
            sequenceFields.emplace_back(offsetFromKey, data, size);
            adjustSizes(offsetFromKey, size);
        }

        size_t getSize() const { return sizeBeforeKey + sizeFromKey; }
    };

	// Override new/delete to allocate from scanner heap
	static void* operator new(size_t size);
	static void operator delete(void* ptr) noexcept;

	StructScanner(size_t maxResults, size_t alignment);
	virtual ~StructScanner();

	static StructScanner* create(size_t maxResults, size_t alignment);

	void setSearchStruct(const StructSearch& targetStruct);

protected:
	// Setup hook - store/update search sequence
	virtual bool setupScanCommon(ScanType scanType, const void* targetValue, size_t valueSize) override;

	// only allow EXACT for first scan
	virtual bool validateFirstScanType(ScanType scanType) override;

	// Chunk scanning - sequence scanner implements memchr based scan
	virtual void scanChunkInRegion(const uint8_t* buffer, size_t chunkSize, uintptr_t chunkBase,
	                               ScanType scanType, const void* targetValue,
	                               std::vector<ScanResult>& localResults, size_t maxLocalResults) override;

	// Rescan pure virtuals - struct scanner implementations
	virtual bool validateValueDirect(uintptr_t address, uintptr_t regionStart, uintptr_t regionEnd,
	                                  ScanType scanType, const void* targetValue,
	                                  ScanResult& outResult) const override;
	virtual bool validateValueInBuffer(const uint8_t* buffer, size_t bufferSize, size_t offset,
	                                    uintptr_t actualAddress, ScanType scanType, const void* targetValue,
	                                    ScanResult& outResult) const override;

	// Getters
	virtual size_t getDataTypeSize() const override;

private:
	// Struct storage
	StructSearch searchStruct;

	// Struct specific helpers
	bool compare(const uint8_t* keyAddr) const;
	bool checkMatch(const uint8_t* keyAddr, ScanType scanType) const;
	bool validateStructDirect(uintptr_t baseAddress, uintptr_t regionStart, uintptr_t regionEnd, ScanType scanType) const;
};

#endif
