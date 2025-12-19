// dllmain.cpp : Defines the entry point for the DLL application.
#include "stdafx.h"
#include "scanner/scanner_heap.h"

BOOL APIENTRY DllMain( HMODULE hModule,
                       DWORD  ul_reason_for_call,
                       LPVOID lpReserved
                     )
{
    switch (ul_reason_for_call)
    {
    case DLL_PROCESS_ATTACH:
        // Initialize scanner heap so we can separate out our
        // copied chunks and results from scans
        ScannerHeap::initialize();
        break;

    case DLL_THREAD_ATTACH:
    case DLL_THREAD_DETACH:
        break;

    case DLL_PROCESS_DETACH:
        // Cleanup scanner heap
        ScannerHeap::cleanup();
        break;
    }
    return TRUE;
}

