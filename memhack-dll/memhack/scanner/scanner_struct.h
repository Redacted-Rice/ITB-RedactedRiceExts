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
        int offset;
        BasicScanner::DataType type;
        ScanValue val;

		// Override new/delete to allocate from scanner heap
        static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;

    	StructFieldBasic(int offset, BasicScanner::DataType type, ScanValue val);
    	~StructFieldBasic() {}

        bool compare(const void* memoryAddr) const;
    };

	// dont use inheritence so they are easily separated and dont have ti deal with delegation
    class StructFieldSequence {
    public:
        int offset;
        std::vector<uint8_t, ScannerAllocator<uint8_t>> val;

		// Override new/delete to allocate from scanner heap
        static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;

    	StructFieldSequence(int offset, const uint8_t* data, size_t size);
    	~StructFieldSequence() {}

        bool compare(const uint8_t* memoryAddr) const;
    };

    class StructSearch {
    public:
        uint8_t searchKey;
        std::vector<StructFieldBasic, ScannerAllocator<StructFieldBasic>> basicFields;
        std::vector<StructFieldSequence, ScannerAllocator<StructFieldSequence>> sequenceFields;
        size_t sizeBeforeKey;
        size_t sizeFromKey;  // Size from key onwards (includes the key byte itself, minimum 1)

    	// Override new/delete to allocate from scanner heap
    	static void* operator new(size_t size);
    	static void operator delete(void* ptr) noexcept;

    	StructSearch(uint8_t key);
    	~StructSearch() {}

    	void adjustSizes(int offset, size_t length) {
    	    // Field spans from key+offset to key+offset+length
    	    // This could overlap or be on either side of the key
    	    if (offset < 0) {
    	        // Field starts before the key
    	        size_t bytesBeforeKey = (size_t)(-offset);
    	        if (bytesBeforeKey > sizeBeforeKey) {
    	            sizeBeforeKey = bytesBeforeKey;
    	        }

    	        // Check if field goes past the key
    	        int fieldEnd = offset + (int)length;
    	        if (fieldEnd > 0) {
    	            if ((size_t)fieldEnd > sizeFromKey) {
    	                sizeFromKey = (size_t)fieldEnd;
    	            }
    	        }
    	    } else {
    	        // Field starts at or after the key
    	        size_t fieldEnd = (size_t)offset + length;
    	        if (fieldEnd > sizeFromKey) {
    	            sizeFromKey = fieldEnd;
    	        }
    	    }
    	}

        void addBasicField(int offset, BasicScanner::DataType type, ScanValue val) {
            basicFields.emplace_back(offset, type, val);
            adjustSizes(offset, BasicScanner::getDataTypeSize(type));
        }

        void addSequenceField(int offset, const uint8_t* data, size_t size) {
            sequenceFields.emplace_back(offset, data, size);
            adjustSizes(offset, size);
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
	bool validateStructDirect(uintptr_t keyAddress, uintptr_t regionStart, uintptr_t regionEnd, ScanType scanType) const;
};

#endif
