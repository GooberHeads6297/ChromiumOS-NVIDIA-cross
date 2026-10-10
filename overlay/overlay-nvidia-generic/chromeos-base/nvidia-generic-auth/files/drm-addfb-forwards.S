.text
.hidden real_drmAddBufs
.global drmAddBufs
.type drmAddBufs, @function
drmAddBufs:
  movq real_drmAddBufs(%rip), %rax
  jmp *%rax
.size drmAddBufs, .-drmAddBufs
.hidden real_drmAddContextPrivateMapping
.global drmAddContextPrivateMapping
.type drmAddContextPrivateMapping, @function
drmAddContextPrivateMapping:
  movq real_drmAddContextPrivateMapping(%rip), %rax
  jmp *%rax
.size drmAddContextPrivateMapping, .-drmAddContextPrivateMapping
.hidden real_drmAddContextTag
.global drmAddContextTag
.type drmAddContextTag, @function
drmAddContextTag:
  movq real_drmAddContextTag(%rip), %rax
  jmp *%rax
.size drmAddContextTag, .-drmAddContextTag
.hidden real_drmAddMap
.global drmAddMap
.type drmAddMap, @function
drmAddMap:
  movq real_drmAddMap(%rip), %rax
  jmp *%rax
.size drmAddMap, .-drmAddMap
.hidden real_drmAgpAcquire
.global drmAgpAcquire
.type drmAgpAcquire, @function
drmAgpAcquire:
  movq real_drmAgpAcquire(%rip), %rax
  jmp *%rax
.size drmAgpAcquire, .-drmAgpAcquire
.hidden real_drmAgpAlloc
.global drmAgpAlloc
.type drmAgpAlloc, @function
drmAgpAlloc:
  movq real_drmAgpAlloc(%rip), %rax
  jmp *%rax
.size drmAgpAlloc, .-drmAgpAlloc
.hidden real_drmAgpBase
.global drmAgpBase
.type drmAgpBase, @function
drmAgpBase:
  movq real_drmAgpBase(%rip), %rax
  jmp *%rax
.size drmAgpBase, .-drmAgpBase
.hidden real_drmAgpBind
.global drmAgpBind
.type drmAgpBind, @function
drmAgpBind:
  movq real_drmAgpBind(%rip), %rax
  jmp *%rax
.size drmAgpBind, .-drmAgpBind
.hidden real_drmAgpDeviceId
.global drmAgpDeviceId
.type drmAgpDeviceId, @function
drmAgpDeviceId:
  movq real_drmAgpDeviceId(%rip), %rax
  jmp *%rax
.size drmAgpDeviceId, .-drmAgpDeviceId
.hidden real_drmAgpEnable
.global drmAgpEnable
.type drmAgpEnable, @function
drmAgpEnable:
  movq real_drmAgpEnable(%rip), %rax
  jmp *%rax
.size drmAgpEnable, .-drmAgpEnable
.hidden real_drmAgpFree
.global drmAgpFree
.type drmAgpFree, @function
drmAgpFree:
  movq real_drmAgpFree(%rip), %rax
  jmp *%rax
.size drmAgpFree, .-drmAgpFree
.hidden real_drmAgpGetMode
.global drmAgpGetMode
.type drmAgpGetMode, @function
drmAgpGetMode:
  movq real_drmAgpGetMode(%rip), %rax
  jmp *%rax
.size drmAgpGetMode, .-drmAgpGetMode
.hidden real_drmAgpMemoryAvail
.global drmAgpMemoryAvail
.type drmAgpMemoryAvail, @function
drmAgpMemoryAvail:
  movq real_drmAgpMemoryAvail(%rip), %rax
  jmp *%rax
.size drmAgpMemoryAvail, .-drmAgpMemoryAvail
.hidden real_drmAgpMemoryUsed
.global drmAgpMemoryUsed
.type drmAgpMemoryUsed, @function
drmAgpMemoryUsed:
  movq real_drmAgpMemoryUsed(%rip), %rax
  jmp *%rax
.size drmAgpMemoryUsed, .-drmAgpMemoryUsed
.hidden real_drmAgpRelease
.global drmAgpRelease
.type drmAgpRelease, @function
drmAgpRelease:
  movq real_drmAgpRelease(%rip), %rax
  jmp *%rax
.size drmAgpRelease, .-drmAgpRelease
.hidden real_drmAgpSize
.global drmAgpSize
.type drmAgpSize, @function
drmAgpSize:
  movq real_drmAgpSize(%rip), %rax
  jmp *%rax
.size drmAgpSize, .-drmAgpSize
.hidden real_drmAgpUnbind
.global drmAgpUnbind
.type drmAgpUnbind, @function
drmAgpUnbind:
  movq real_drmAgpUnbind(%rip), %rax
  jmp *%rax
.size drmAgpUnbind, .-drmAgpUnbind
.hidden real_drmAgpVendorId
.global drmAgpVendorId
.type drmAgpVendorId, @function
drmAgpVendorId:
  movq real_drmAgpVendorId(%rip), %rax
  jmp *%rax
.size drmAgpVendorId, .-drmAgpVendorId
.hidden real_drmAgpVersionMajor
.global drmAgpVersionMajor
.type drmAgpVersionMajor, @function
drmAgpVersionMajor:
  movq real_drmAgpVersionMajor(%rip), %rax
  jmp *%rax
.size drmAgpVersionMajor, .-drmAgpVersionMajor
.hidden real_drmAgpVersionMinor
.global drmAgpVersionMinor
.type drmAgpVersionMinor, @function
drmAgpVersionMinor:
  movq real_drmAgpVersionMinor(%rip), %rax
  jmp *%rax
.size drmAgpVersionMinor, .-drmAgpVersionMinor
.hidden real_drmAuthMagic
.global drmAuthMagic
.type drmAuthMagic, @function
drmAuthMagic:
  movq real_drmAuthMagic(%rip), %rax
  jmp *%rax
.size drmAuthMagic, .-drmAuthMagic
.hidden real_drmAvailable
.global drmAvailable
.type drmAvailable, @function
drmAvailable:
  movq real_drmAvailable(%rip), %rax
  jmp *%rax
.size drmAvailable, .-drmAvailable
.hidden real_drmCheckModesettingSupported
.global drmCheckModesettingSupported
.type drmCheckModesettingSupported, @function
drmCheckModesettingSupported:
  movq real_drmCheckModesettingSupported(%rip), %rax
  jmp *%rax
.size drmCheckModesettingSupported, .-drmCheckModesettingSupported
.hidden real_drmClose
.global drmClose
.type drmClose, @function
drmClose:
  movq real_drmClose(%rip), %rax
  jmp *%rax
.size drmClose, .-drmClose
.hidden real_drmCloseBufferHandle
.global drmCloseBufferHandle
.type drmCloseBufferHandle, @function
drmCloseBufferHandle:
  movq real_drmCloseBufferHandle(%rip), %rax
  jmp *%rax
.size drmCloseBufferHandle, .-drmCloseBufferHandle
.hidden real_drmCloseOnce
.global drmCloseOnce
.type drmCloseOnce, @function
drmCloseOnce:
  movq real_drmCloseOnce(%rip), %rax
  jmp *%rax
.size drmCloseOnce, .-drmCloseOnce
.hidden real_drmCommandNone
.global drmCommandNone
.type drmCommandNone, @function
drmCommandNone:
  movq real_drmCommandNone(%rip), %rax
  jmp *%rax
.size drmCommandNone, .-drmCommandNone
.hidden real_drmCommandRead
.global drmCommandRead
.type drmCommandRead, @function
drmCommandRead:
  movq real_drmCommandRead(%rip), %rax
  jmp *%rax
.size drmCommandRead, .-drmCommandRead
.hidden real_drmCommandWrite
.global drmCommandWrite
.type drmCommandWrite, @function
drmCommandWrite:
  movq real_drmCommandWrite(%rip), %rax
  jmp *%rax
.size drmCommandWrite, .-drmCommandWrite
.hidden real_drmCommandWriteRead
.global drmCommandWriteRead
.type drmCommandWriteRead, @function
drmCommandWriteRead:
  movq real_drmCommandWriteRead(%rip), %rax
  jmp *%rax
.size drmCommandWriteRead, .-drmCommandWriteRead
.hidden real_drmCreateContext
.global drmCreateContext
.type drmCreateContext, @function
drmCreateContext:
  movq real_drmCreateContext(%rip), %rax
  jmp *%rax
.size drmCreateContext, .-drmCreateContext
.hidden real_drmCreateDrawable
.global drmCreateDrawable
.type drmCreateDrawable, @function
drmCreateDrawable:
  movq real_drmCreateDrawable(%rip), %rax
  jmp *%rax
.size drmCreateDrawable, .-drmCreateDrawable
.hidden real_drmCrtcGetSequence
.global drmCrtcGetSequence
.type drmCrtcGetSequence, @function
drmCrtcGetSequence:
  movq real_drmCrtcGetSequence(%rip), %rax
  jmp *%rax
.size drmCrtcGetSequence, .-drmCrtcGetSequence
.hidden real_drmCrtcQueueSequence
.global drmCrtcQueueSequence
.type drmCrtcQueueSequence, @function
drmCrtcQueueSequence:
  movq real_drmCrtcQueueSequence(%rip), %rax
  jmp *%rax
.size drmCrtcQueueSequence, .-drmCrtcQueueSequence
.hidden real_drmCtlInstHandler
.global drmCtlInstHandler
.type drmCtlInstHandler, @function
drmCtlInstHandler:
  movq real_drmCtlInstHandler(%rip), %rax
  jmp *%rax
.size drmCtlInstHandler, .-drmCtlInstHandler
.hidden real_drmCtlUninstHandler
.global drmCtlUninstHandler
.type drmCtlUninstHandler, @function
drmCtlUninstHandler:
  movq real_drmCtlUninstHandler(%rip), %rax
  jmp *%rax
.size drmCtlUninstHandler, .-drmCtlUninstHandler
.hidden real_drmDelContextTag
.global drmDelContextTag
.type drmDelContextTag, @function
drmDelContextTag:
  movq real_drmDelContextTag(%rip), %rax
  jmp *%rax
.size drmDelContextTag, .-drmDelContextTag
.hidden real_drmDestroyContext
.global drmDestroyContext
.type drmDestroyContext, @function
drmDestroyContext:
  movq real_drmDestroyContext(%rip), %rax
  jmp *%rax
.size drmDestroyContext, .-drmDestroyContext
.hidden real_drmDestroyDrawable
.global drmDestroyDrawable
.type drmDestroyDrawable, @function
drmDestroyDrawable:
  movq real_drmDestroyDrawable(%rip), %rax
  jmp *%rax
.size drmDestroyDrawable, .-drmDestroyDrawable
.hidden real_drmDevicesEqual
.global drmDevicesEqual
.type drmDevicesEqual, @function
drmDevicesEqual:
  movq real_drmDevicesEqual(%rip), %rax
  jmp *%rax
.size drmDevicesEqual, .-drmDevicesEqual
.hidden real_drmDMA
.global drmDMA
.type drmDMA, @function
drmDMA:
  movq real_drmDMA(%rip), %rax
  jmp *%rax
.size drmDMA, .-drmDMA
.hidden real_drmDropMaster
.global drmDropMaster
.type drmDropMaster, @function
drmDropMaster:
  movq real_drmDropMaster(%rip), %rax
  jmp *%rax
.size drmDropMaster, .-drmDropMaster
.hidden real_drmError
.global drmError
.type drmError, @function
drmError:
  movq real_drmError(%rip), %rax
  jmp *%rax
.size drmError, .-drmError
.hidden real_drmFinish
.global drmFinish
.type drmFinish, @function
drmFinish:
  movq real_drmFinish(%rip), %rax
  jmp *%rax
.size drmFinish, .-drmFinish
.hidden real_drmFree
.global drmFree
.type drmFree, @function
drmFree:
  movq real_drmFree(%rip), %rax
  jmp *%rax
.size drmFree, .-drmFree
.hidden real_drmFreeBufs
.global drmFreeBufs
.type drmFreeBufs, @function
drmFreeBufs:
  movq real_drmFreeBufs(%rip), %rax
  jmp *%rax
.size drmFreeBufs, .-drmFreeBufs
.hidden real_drmFreeBusid
.global drmFreeBusid
.type drmFreeBusid, @function
drmFreeBusid:
  movq real_drmFreeBusid(%rip), %rax
  jmp *%rax
.size drmFreeBusid, .-drmFreeBusid
.hidden real_drmFreeDevice
.global drmFreeDevice
.type drmFreeDevice, @function
drmFreeDevice:
  movq real_drmFreeDevice(%rip), %rax
  jmp *%rax
.size drmFreeDevice, .-drmFreeDevice
.hidden real_drmFreeDevices
.global drmFreeDevices
.type drmFreeDevices, @function
drmFreeDevices:
  movq real_drmFreeDevices(%rip), %rax
  jmp *%rax
.size drmFreeDevices, .-drmFreeDevices
.hidden real_drmFreeReservedContextList
.global drmFreeReservedContextList
.type drmFreeReservedContextList, @function
drmFreeReservedContextList:
  movq real_drmFreeReservedContextList(%rip), %rax
  jmp *%rax
.size drmFreeReservedContextList, .-drmFreeReservedContextList
.hidden real_drmFreeVersion
.global drmFreeVersion
.type drmFreeVersion, @function
drmFreeVersion:
  movq real_drmFreeVersion(%rip), %rax
  jmp *%rax
.size drmFreeVersion, .-drmFreeVersion
.hidden real_drmGetBufInfo
.global drmGetBufInfo
.type drmGetBufInfo, @function
drmGetBufInfo:
  movq real_drmGetBufInfo(%rip), %rax
  jmp *%rax
.size drmGetBufInfo, .-drmGetBufInfo
.hidden real_drmGetBusid
.global drmGetBusid
.type drmGetBusid, @function
drmGetBusid:
  movq real_drmGetBusid(%rip), %rax
  jmp *%rax
.size drmGetBusid, .-drmGetBusid
.hidden real_drmGetCap
.global drmGetCap
.type drmGetCap, @function
drmGetCap:
  movq real_drmGetCap(%rip), %rax
  jmp *%rax
.size drmGetCap, .-drmGetCap
.hidden real_drmGetClient
.global drmGetClient
.type drmGetClient, @function
drmGetClient:
  movq real_drmGetClient(%rip), %rax
  jmp *%rax
.size drmGetClient, .-drmGetClient
.hidden real_drmGetContextFlags
.global drmGetContextFlags
.type drmGetContextFlags, @function
drmGetContextFlags:
  movq real_drmGetContextFlags(%rip), %rax
  jmp *%rax
.size drmGetContextFlags, .-drmGetContextFlags
.hidden real_drmGetContextPrivateMapping
.global drmGetContextPrivateMapping
.type drmGetContextPrivateMapping, @function
drmGetContextPrivateMapping:
  movq real_drmGetContextPrivateMapping(%rip), %rax
  jmp *%rax
.size drmGetContextPrivateMapping, .-drmGetContextPrivateMapping
.hidden real_drmGetContextTag
.global drmGetContextTag
.type drmGetContextTag, @function
drmGetContextTag:
  movq real_drmGetContextTag(%rip), %rax
  jmp *%rax
.size drmGetContextTag, .-drmGetContextTag
.hidden real_drmGetDevice
.global drmGetDevice
.type drmGetDevice, @function
drmGetDevice:
  movq real_drmGetDevice(%rip), %rax
  jmp *%rax
.size drmGetDevice, .-drmGetDevice
.hidden real_drmGetDevice2
.global drmGetDevice2
.type drmGetDevice2, @function
drmGetDevice2:
  movq real_drmGetDevice2(%rip), %rax
  jmp *%rax
.size drmGetDevice2, .-drmGetDevice2
.hidden real_drmGetDeviceFromDevId
.global drmGetDeviceFromDevId
.type drmGetDeviceFromDevId, @function
drmGetDeviceFromDevId:
  movq real_drmGetDeviceFromDevId(%rip), %rax
  jmp *%rax
.size drmGetDeviceFromDevId, .-drmGetDeviceFromDevId
.hidden real_drmGetDeviceNameFromFd
.global drmGetDeviceNameFromFd
.type drmGetDeviceNameFromFd, @function
drmGetDeviceNameFromFd:
  movq real_drmGetDeviceNameFromFd(%rip), %rax
  jmp *%rax
.size drmGetDeviceNameFromFd, .-drmGetDeviceNameFromFd
.hidden real_drmGetDeviceNameFromFd2
.global drmGetDeviceNameFromFd2
.type drmGetDeviceNameFromFd2, @function
drmGetDeviceNameFromFd2:
  movq real_drmGetDeviceNameFromFd2(%rip), %rax
  jmp *%rax
.size drmGetDeviceNameFromFd2, .-drmGetDeviceNameFromFd2
.hidden real_drmGetDevices
.global drmGetDevices
.type drmGetDevices, @function
drmGetDevices:
  movq real_drmGetDevices(%rip), %rax
  jmp *%rax
.size drmGetDevices, .-drmGetDevices
.hidden real_drmGetDevices2
.global drmGetDevices2
.type drmGetDevices2, @function
drmGetDevices2:
  movq real_drmGetDevices2(%rip), %rax
  jmp *%rax
.size drmGetDevices2, .-drmGetDevices2
.hidden real_drmGetEntry
.global drmGetEntry
.type drmGetEntry, @function
drmGetEntry:
  movq real_drmGetEntry(%rip), %rax
  jmp *%rax
.size drmGetEntry, .-drmGetEntry
.hidden real_drmGetFormatModifierName
.global drmGetFormatModifierName
.type drmGetFormatModifierName, @function
drmGetFormatModifierName:
  movq real_drmGetFormatModifierName(%rip), %rax
  jmp *%rax
.size drmGetFormatModifierName, .-drmGetFormatModifierName
.hidden real_drmGetFormatModifierVendor
.global drmGetFormatModifierVendor
.type drmGetFormatModifierVendor, @function
drmGetFormatModifierVendor:
  movq real_drmGetFormatModifierVendor(%rip), %rax
  jmp *%rax
.size drmGetFormatModifierVendor, .-drmGetFormatModifierVendor
.hidden real_drmGetFormatName
.global drmGetFormatName
.type drmGetFormatName, @function
drmGetFormatName:
  movq real_drmGetFormatName(%rip), %rax
  jmp *%rax
.size drmGetFormatName, .-drmGetFormatName
.hidden real_drmGetHashTable
.global drmGetHashTable
.type drmGetHashTable, @function
drmGetHashTable:
  movq real_drmGetHashTable(%rip), %rax
  jmp *%rax
.size drmGetHashTable, .-drmGetHashTable
.hidden real_drmGetInterruptFromBusID
.global drmGetInterruptFromBusID
.type drmGetInterruptFromBusID, @function
drmGetInterruptFromBusID:
  movq real_drmGetInterruptFromBusID(%rip), %rax
  jmp *%rax
.size drmGetInterruptFromBusID, .-drmGetInterruptFromBusID
.hidden real_drmGetLibVersion
.global drmGetLibVersion
.type drmGetLibVersion, @function
drmGetLibVersion:
  movq real_drmGetLibVersion(%rip), %rax
  jmp *%rax
.size drmGetLibVersion, .-drmGetLibVersion
.hidden real_drmGetLock
.global drmGetLock
.type drmGetLock, @function
drmGetLock:
  movq real_drmGetLock(%rip), %rax
  jmp *%rax
.size drmGetLock, .-drmGetLock
.hidden real_drmGetMagic
.global drmGetMagic
.type drmGetMagic, @function
drmGetMagic:
  movq real_drmGetMagic(%rip), %rax
  jmp *%rax
.size drmGetMagic, .-drmGetMagic
.hidden real_drmGetMap
.global drmGetMap
.type drmGetMap, @function
drmGetMap:
  movq real_drmGetMap(%rip), %rax
  jmp *%rax
.size drmGetMap, .-drmGetMap
.hidden real_drmGetNodeTypeFromDevId
.global drmGetNodeTypeFromDevId
.type drmGetNodeTypeFromDevId, @function
drmGetNodeTypeFromDevId:
  movq real_drmGetNodeTypeFromDevId(%rip), %rax
  jmp *%rax
.size drmGetNodeTypeFromDevId, .-drmGetNodeTypeFromDevId
.hidden real_drmGetNodeTypeFromFd
.global drmGetNodeTypeFromFd
.type drmGetNodeTypeFromFd, @function
drmGetNodeTypeFromFd:
  movq real_drmGetNodeTypeFromFd(%rip), %rax
  jmp *%rax
.size drmGetNodeTypeFromFd, .-drmGetNodeTypeFromFd
.hidden real_drmGetPrimaryDeviceNameFromFd
.global drmGetPrimaryDeviceNameFromFd
.type drmGetPrimaryDeviceNameFromFd, @function
drmGetPrimaryDeviceNameFromFd:
  movq real_drmGetPrimaryDeviceNameFromFd(%rip), %rax
  jmp *%rax
.size drmGetPrimaryDeviceNameFromFd, .-drmGetPrimaryDeviceNameFromFd
.hidden real_drmGetRenderDeviceNameFromFd
.global drmGetRenderDeviceNameFromFd
.type drmGetRenderDeviceNameFromFd, @function
drmGetRenderDeviceNameFromFd:
  movq real_drmGetRenderDeviceNameFromFd(%rip), %rax
  jmp *%rax
.size drmGetRenderDeviceNameFromFd, .-drmGetRenderDeviceNameFromFd
.hidden real_drmGetReservedContextList
.global drmGetReservedContextList
.type drmGetReservedContextList, @function
drmGetReservedContextList:
  movq real_drmGetReservedContextList(%rip), %rax
  jmp *%rax
.size drmGetReservedContextList, .-drmGetReservedContextList
.hidden real_drmGetStats
.global drmGetStats
.type drmGetStats, @function
drmGetStats:
  movq real_drmGetStats(%rip), %rax
  jmp *%rax
.size drmGetStats, .-drmGetStats
.hidden real_drmGetVersion
.global drmGetVersion
.type drmGetVersion, @function
drmGetVersion:
  movq real_drmGetVersion(%rip), %rax
  jmp *%rax
.size drmGetVersion, .-drmGetVersion
.hidden real_drmHandleEvent
.global drmHandleEvent
.type drmHandleEvent, @function
drmHandleEvent:
  movq real_drmHandleEvent(%rip), %rax
  jmp *%rax
.size drmHandleEvent, .-drmHandleEvent
.hidden real_drmHashCreate
.global drmHashCreate
.type drmHashCreate, @function
drmHashCreate:
  movq real_drmHashCreate(%rip), %rax
  jmp *%rax
.size drmHashCreate, .-drmHashCreate
.hidden real_drmHashDelete
.global drmHashDelete
.type drmHashDelete, @function
drmHashDelete:
  movq real_drmHashDelete(%rip), %rax
  jmp *%rax
.size drmHashDelete, .-drmHashDelete
.hidden real_drmHashDestroy
.global drmHashDestroy
.type drmHashDestroy, @function
drmHashDestroy:
  movq real_drmHashDestroy(%rip), %rax
  jmp *%rax
.size drmHashDestroy, .-drmHashDestroy
.hidden real_drmHashFirst
.global drmHashFirst
.type drmHashFirst, @function
drmHashFirst:
  movq real_drmHashFirst(%rip), %rax
  jmp *%rax
.size drmHashFirst, .-drmHashFirst
.hidden real_drmHashInsert
.global drmHashInsert
.type drmHashInsert, @function
drmHashInsert:
  movq real_drmHashInsert(%rip), %rax
  jmp *%rax
.size drmHashInsert, .-drmHashInsert
.hidden real_drmHashLookup
.global drmHashLookup
.type drmHashLookup, @function
drmHashLookup:
  movq real_drmHashLookup(%rip), %rax
  jmp *%rax
.size drmHashLookup, .-drmHashLookup
.hidden real_drmHashNext
.global drmHashNext
.type drmHashNext, @function
drmHashNext:
  movq real_drmHashNext(%rip), %rax
  jmp *%rax
.size drmHashNext, .-drmHashNext
.hidden real_drmIsKMS
.global drmIsKMS
.type drmIsKMS, @function
drmIsKMS:
  movq real_drmIsKMS(%rip), %rax
  jmp *%rax
.size drmIsKMS, .-drmIsKMS
.hidden real_drmIsMaster
.global drmIsMaster
.type drmIsMaster, @function
drmIsMaster:
  movq real_drmIsMaster(%rip), %rax
  jmp *%rax
.size drmIsMaster, .-drmIsMaster
.hidden real_drmMalloc
.global drmMalloc
.type drmMalloc, @function
drmMalloc:
  movq real_drmMalloc(%rip), %rax
  jmp *%rax
.size drmMalloc, .-drmMalloc
.hidden real_drmMap
.global drmMap
.type drmMap, @function
drmMap:
  movq real_drmMap(%rip), %rax
  jmp *%rax
.size drmMap, .-drmMap
.hidden real_drmMapBufs
.global drmMapBufs
.type drmMapBufs, @function
drmMapBufs:
  movq real_drmMapBufs(%rip), %rax
  jmp *%rax
.size drmMapBufs, .-drmMapBufs
.hidden real_drmMarkBufs
.global drmMarkBufs
.type drmMarkBufs, @function
drmMarkBufs:
  movq real_drmMarkBufs(%rip), %rax
  jmp *%rax
.size drmMarkBufs, .-drmMarkBufs
.hidden real_drmModeAddFB
.global drmModeAddFB
.type drmModeAddFB, @function
drmModeAddFB:
  movq real_drmModeAddFB(%rip), %rax
  jmp *%rax
.size drmModeAddFB, .-drmModeAddFB
.hidden real_drmModeAtomicAddProperty
.global drmModeAtomicAddProperty
.type drmModeAtomicAddProperty, @function
drmModeAtomicAddProperty:
  movq real_drmModeAtomicAddProperty(%rip), %rax
  jmp *%rax
.size drmModeAtomicAddProperty, .-drmModeAtomicAddProperty
.hidden real_drmModeAtomicAlloc
.global drmModeAtomicAlloc
.type drmModeAtomicAlloc, @function
drmModeAtomicAlloc:
  movq real_drmModeAtomicAlloc(%rip), %rax
  jmp *%rax
.size drmModeAtomicAlloc, .-drmModeAtomicAlloc
.hidden real_drmModeAtomicDuplicate
.global drmModeAtomicDuplicate
.type drmModeAtomicDuplicate, @function
drmModeAtomicDuplicate:
  movq real_drmModeAtomicDuplicate(%rip), %rax
  jmp *%rax
.size drmModeAtomicDuplicate, .-drmModeAtomicDuplicate
.hidden real_drmModeAtomicFree
.global drmModeAtomicFree
.type drmModeAtomicFree, @function
drmModeAtomicFree:
  movq real_drmModeAtomicFree(%rip), %rax
  jmp *%rax
.size drmModeAtomicFree, .-drmModeAtomicFree
.hidden real_drmModeAtomicGetCursor
.global drmModeAtomicGetCursor
.type drmModeAtomicGetCursor, @function
drmModeAtomicGetCursor:
  movq real_drmModeAtomicGetCursor(%rip), %rax
  jmp *%rax
.size drmModeAtomicGetCursor, .-drmModeAtomicGetCursor
.hidden real_drmModeAtomicMerge
.global drmModeAtomicMerge
.type drmModeAtomicMerge, @function
drmModeAtomicMerge:
  movq real_drmModeAtomicMerge(%rip), %rax
  jmp *%rax
.size drmModeAtomicMerge, .-drmModeAtomicMerge
.hidden real_drmModeAtomicSetCursor
.global drmModeAtomicSetCursor
.type drmModeAtomicSetCursor, @function
drmModeAtomicSetCursor:
  movq real_drmModeAtomicSetCursor(%rip), %rax
  jmp *%rax
.size drmModeAtomicSetCursor, .-drmModeAtomicSetCursor
.hidden real_drmModeAttachMode
.global drmModeAttachMode
.type drmModeAttachMode, @function
drmModeAttachMode:
  movq real_drmModeAttachMode(%rip), %rax
  jmp *%rax
.size drmModeAttachMode, .-drmModeAttachMode
.hidden real_drmModeCloseFB
.global drmModeCloseFB
.type drmModeCloseFB, @function
drmModeCloseFB:
  movq real_drmModeCloseFB(%rip), %rax
  jmp *%rax
.size drmModeCloseFB, .-drmModeCloseFB
.hidden real_drmModeConnectorGetPossibleCrtcs
.global drmModeConnectorGetPossibleCrtcs
.type drmModeConnectorGetPossibleCrtcs, @function
drmModeConnectorGetPossibleCrtcs:
  movq real_drmModeConnectorGetPossibleCrtcs(%rip), %rax
  jmp *%rax
.size drmModeConnectorGetPossibleCrtcs, .-drmModeConnectorGetPossibleCrtcs
.hidden real_drmModeConnectorSetProperty
.global drmModeConnectorSetProperty
.type drmModeConnectorSetProperty, @function
drmModeConnectorSetProperty:
  movq real_drmModeConnectorSetProperty(%rip), %rax
  jmp *%rax
.size drmModeConnectorSetProperty, .-drmModeConnectorSetProperty
.hidden real_drmModeCreateDumbBuffer
.global drmModeCreateDumbBuffer
.type drmModeCreateDumbBuffer, @function
drmModeCreateDumbBuffer:
  movq real_drmModeCreateDumbBuffer(%rip), %rax
  jmp *%rax
.size drmModeCreateDumbBuffer, .-drmModeCreateDumbBuffer
.hidden real_drmModeCreateLease
.global drmModeCreateLease
.type drmModeCreateLease, @function
drmModeCreateLease:
  movq real_drmModeCreateLease(%rip), %rax
  jmp *%rax
.size drmModeCreateLease, .-drmModeCreateLease
.hidden real_drmModeCreatePropertyBlob
.global drmModeCreatePropertyBlob
.type drmModeCreatePropertyBlob, @function
drmModeCreatePropertyBlob:
  movq real_drmModeCreatePropertyBlob(%rip), %rax
  jmp *%rax
.size drmModeCreatePropertyBlob, .-drmModeCreatePropertyBlob
.hidden real_drmModeCrtcGetGamma
.global drmModeCrtcGetGamma
.type drmModeCrtcGetGamma, @function
drmModeCrtcGetGamma:
  movq real_drmModeCrtcGetGamma(%rip), %rax
  jmp *%rax
.size drmModeCrtcGetGamma, .-drmModeCrtcGetGamma
.hidden real_drmModeCrtcSetGamma
.global drmModeCrtcSetGamma
.type drmModeCrtcSetGamma, @function
drmModeCrtcSetGamma:
  movq real_drmModeCrtcSetGamma(%rip), %rax
  jmp *%rax
.size drmModeCrtcSetGamma, .-drmModeCrtcSetGamma
.hidden real_drmModeDestroyDumbBuffer
.global drmModeDestroyDumbBuffer
.type drmModeDestroyDumbBuffer, @function
drmModeDestroyDumbBuffer:
  movq real_drmModeDestroyDumbBuffer(%rip), %rax
  jmp *%rax
.size drmModeDestroyDumbBuffer, .-drmModeDestroyDumbBuffer
.hidden real_drmModeDestroyPropertyBlob
.global drmModeDestroyPropertyBlob
.type drmModeDestroyPropertyBlob, @function
drmModeDestroyPropertyBlob:
  movq real_drmModeDestroyPropertyBlob(%rip), %rax
  jmp *%rax
.size drmModeDestroyPropertyBlob, .-drmModeDestroyPropertyBlob
.hidden real_drmModeDetachMode
.global drmModeDetachMode
.type drmModeDetachMode, @function
drmModeDetachMode:
  movq real_drmModeDetachMode(%rip), %rax
  jmp *%rax
.size drmModeDetachMode, .-drmModeDetachMode
.hidden real_drmModeDirtyFB
.global drmModeDirtyFB
.type drmModeDirtyFB, @function
drmModeDirtyFB:
  movq real_drmModeDirtyFB(%rip), %rax
  jmp *%rax
.size drmModeDirtyFB, .-drmModeDirtyFB
.hidden real_drmModeFormatModifierBlobIterNext
.global drmModeFormatModifierBlobIterNext
.type drmModeFormatModifierBlobIterNext, @function
drmModeFormatModifierBlobIterNext:
  movq real_drmModeFormatModifierBlobIterNext(%rip), %rax
  jmp *%rax
.size drmModeFormatModifierBlobIterNext, .-drmModeFormatModifierBlobIterNext
.hidden real_drmModeFreeConnector
.global drmModeFreeConnector
.type drmModeFreeConnector, @function
drmModeFreeConnector:
  movq real_drmModeFreeConnector(%rip), %rax
  jmp *%rax
.size drmModeFreeConnector, .-drmModeFreeConnector
.hidden real_drmModeFreeCrtc
.global drmModeFreeCrtc
.type drmModeFreeCrtc, @function
drmModeFreeCrtc:
  movq real_drmModeFreeCrtc(%rip), %rax
  jmp *%rax
.size drmModeFreeCrtc, .-drmModeFreeCrtc
.hidden real_drmModeFreeEncoder
.global drmModeFreeEncoder
.type drmModeFreeEncoder, @function
drmModeFreeEncoder:
  movq real_drmModeFreeEncoder(%rip), %rax
  jmp *%rax
.size drmModeFreeEncoder, .-drmModeFreeEncoder
.hidden real_drmModeFreeFB
.global drmModeFreeFB
.type drmModeFreeFB, @function
drmModeFreeFB:
  movq real_drmModeFreeFB(%rip), %rax
  jmp *%rax
.size drmModeFreeFB, .-drmModeFreeFB
.hidden real_drmModeFreeFB2
.global drmModeFreeFB2
.type drmModeFreeFB2, @function
drmModeFreeFB2:
  movq real_drmModeFreeFB2(%rip), %rax
  jmp *%rax
.size drmModeFreeFB2, .-drmModeFreeFB2
.hidden real_drmModeFreeModeInfo
.global drmModeFreeModeInfo
.type drmModeFreeModeInfo, @function
drmModeFreeModeInfo:
  movq real_drmModeFreeModeInfo(%rip), %rax
  jmp *%rax
.size drmModeFreeModeInfo, .-drmModeFreeModeInfo
.hidden real_drmModeFreeObjectProperties
.global drmModeFreeObjectProperties
.type drmModeFreeObjectProperties, @function
drmModeFreeObjectProperties:
  movq real_drmModeFreeObjectProperties(%rip), %rax
  jmp *%rax
.size drmModeFreeObjectProperties, .-drmModeFreeObjectProperties
.hidden real_drmModeFreePlane
.global drmModeFreePlane
.type drmModeFreePlane, @function
drmModeFreePlane:
  movq real_drmModeFreePlane(%rip), %rax
  jmp *%rax
.size drmModeFreePlane, .-drmModeFreePlane
.hidden real_drmModeFreePlaneResources
.global drmModeFreePlaneResources
.type drmModeFreePlaneResources, @function
drmModeFreePlaneResources:
  movq real_drmModeFreePlaneResources(%rip), %rax
  jmp *%rax
.size drmModeFreePlaneResources, .-drmModeFreePlaneResources
.hidden real_drmModeFreeProperty
.global drmModeFreeProperty
.type drmModeFreeProperty, @function
drmModeFreeProperty:
  movq real_drmModeFreeProperty(%rip), %rax
  jmp *%rax
.size drmModeFreeProperty, .-drmModeFreeProperty
.hidden real_drmModeFreePropertyBlob
.global drmModeFreePropertyBlob
.type drmModeFreePropertyBlob, @function
drmModeFreePropertyBlob:
  movq real_drmModeFreePropertyBlob(%rip), %rax
  jmp *%rax
.size drmModeFreePropertyBlob, .-drmModeFreePropertyBlob
.hidden real_drmModeFreeResources
.global drmModeFreeResources
.type drmModeFreeResources, @function
drmModeFreeResources:
  movq real_drmModeFreeResources(%rip), %rax
  jmp *%rax
.size drmModeFreeResources, .-drmModeFreeResources
.hidden real_drmModeGetConnector
.global drmModeGetConnector
.type drmModeGetConnector, @function
drmModeGetConnector:
  movq real_drmModeGetConnector(%rip), %rax
  jmp *%rax
.size drmModeGetConnector, .-drmModeGetConnector
.hidden real_drmModeGetConnectorCurrent
.global drmModeGetConnectorCurrent
.type drmModeGetConnectorCurrent, @function
drmModeGetConnectorCurrent:
  movq real_drmModeGetConnectorCurrent(%rip), %rax
  jmp *%rax
.size drmModeGetConnectorCurrent, .-drmModeGetConnectorCurrent
.hidden real_drmModeGetConnectorTypeName
.global drmModeGetConnectorTypeName
.type drmModeGetConnectorTypeName, @function
drmModeGetConnectorTypeName:
  movq real_drmModeGetConnectorTypeName(%rip), %rax
  jmp *%rax
.size drmModeGetConnectorTypeName, .-drmModeGetConnectorTypeName
.hidden real_drmModeGetCrtc
.global drmModeGetCrtc
.type drmModeGetCrtc, @function
drmModeGetCrtc:
  movq real_drmModeGetCrtc(%rip), %rax
  jmp *%rax
.size drmModeGetCrtc, .-drmModeGetCrtc
.hidden real_drmModeGetEncoder
.global drmModeGetEncoder
.type drmModeGetEncoder, @function
drmModeGetEncoder:
  movq real_drmModeGetEncoder(%rip), %rax
  jmp *%rax
.size drmModeGetEncoder, .-drmModeGetEncoder
.hidden real_drmModeGetFB
.global drmModeGetFB
.type drmModeGetFB, @function
drmModeGetFB:
  movq real_drmModeGetFB(%rip), %rax
  jmp *%rax
.size drmModeGetFB, .-drmModeGetFB
.hidden real_drmModeGetFB2
.global drmModeGetFB2
.type drmModeGetFB2, @function
drmModeGetFB2:
  movq real_drmModeGetFB2(%rip), %rax
  jmp *%rax
.size drmModeGetFB2, .-drmModeGetFB2
.hidden real_drmModeGetLease
.global drmModeGetLease
.type drmModeGetLease, @function
drmModeGetLease:
  movq real_drmModeGetLease(%rip), %rax
  jmp *%rax
.size drmModeGetLease, .-drmModeGetLease
.hidden real_drmModeGetPlane
.global drmModeGetPlane
.type drmModeGetPlane, @function
drmModeGetPlane:
  movq real_drmModeGetPlane(%rip), %rax
  jmp *%rax
.size drmModeGetPlane, .-drmModeGetPlane
.hidden real_drmModeGetPlaneResources
.global drmModeGetPlaneResources
.type drmModeGetPlaneResources, @function
drmModeGetPlaneResources:
  movq real_drmModeGetPlaneResources(%rip), %rax
  jmp *%rax
.size drmModeGetPlaneResources, .-drmModeGetPlaneResources
.hidden real_drmModeGetProperty
.global drmModeGetProperty
.type drmModeGetProperty, @function
drmModeGetProperty:
  movq real_drmModeGetProperty(%rip), %rax
  jmp *%rax
.size drmModeGetProperty, .-drmModeGetProperty
.hidden real_drmModeGetPropertyBlob
.global drmModeGetPropertyBlob
.type drmModeGetPropertyBlob, @function
drmModeGetPropertyBlob:
  movq real_drmModeGetPropertyBlob(%rip), %rax
  jmp *%rax
.size drmModeGetPropertyBlob, .-drmModeGetPropertyBlob
.hidden real_drmModeGetResources
.global drmModeGetResources
.type drmModeGetResources, @function
drmModeGetResources:
  movq real_drmModeGetResources(%rip), %rax
  jmp *%rax
.size drmModeGetResources, .-drmModeGetResources
.hidden real_drmModeListLessees
.global drmModeListLessees
.type drmModeListLessees, @function
drmModeListLessees:
  movq real_drmModeListLessees(%rip), %rax
  jmp *%rax
.size drmModeListLessees, .-drmModeListLessees
.hidden real_drmModeMapDumbBuffer
.global drmModeMapDumbBuffer
.type drmModeMapDumbBuffer, @function
drmModeMapDumbBuffer:
  movq real_drmModeMapDumbBuffer(%rip), %rax
  jmp *%rax
.size drmModeMapDumbBuffer, .-drmModeMapDumbBuffer
.hidden real_drmModeMoveCursor
.global drmModeMoveCursor
.type drmModeMoveCursor, @function
drmModeMoveCursor:
  movq real_drmModeMoveCursor(%rip), %rax
  jmp *%rax
.size drmModeMoveCursor, .-drmModeMoveCursor
.hidden real_drmModeObjectGetProperties
.global drmModeObjectGetProperties
.type drmModeObjectGetProperties, @function
drmModeObjectGetProperties:
  movq real_drmModeObjectGetProperties(%rip), %rax
  jmp *%rax
.size drmModeObjectGetProperties, .-drmModeObjectGetProperties
.hidden real_drmModeObjectSetProperty
.global drmModeObjectSetProperty
.type drmModeObjectSetProperty, @function
drmModeObjectSetProperty:
  movq real_drmModeObjectSetProperty(%rip), %rax
  jmp *%rax
.size drmModeObjectSetProperty, .-drmModeObjectSetProperty
.hidden real_drmModePageFlipTarget
.global drmModePageFlipTarget
.type drmModePageFlipTarget, @function
drmModePageFlipTarget:
  movq real_drmModePageFlipTarget(%rip), %rax
  jmp *%rax
.size drmModePageFlipTarget, .-drmModePageFlipTarget
.hidden real_drmModeRevokeLease
.global drmModeRevokeLease
.type drmModeRevokeLease, @function
drmModeRevokeLease:
  movq real_drmModeRevokeLease(%rip), %rax
  jmp *%rax
.size drmModeRevokeLease, .-drmModeRevokeLease
.hidden real_drmModeRmFB
.global drmModeRmFB
.type drmModeRmFB, @function
drmModeRmFB:
  movq real_drmModeRmFB(%rip), %rax
  jmp *%rax
.size drmModeRmFB, .-drmModeRmFB
.hidden real_drmModeSetCursor
.global drmModeSetCursor
.type drmModeSetCursor, @function
drmModeSetCursor:
  movq real_drmModeSetCursor(%rip), %rax
  jmp *%rax
.size drmModeSetCursor, .-drmModeSetCursor
.hidden real_drmModeSetCursor2
.global drmModeSetCursor2
.type drmModeSetCursor2, @function
drmModeSetCursor2:
  movq real_drmModeSetCursor2(%rip), %rax
  jmp *%rax
.size drmModeSetCursor2, .-drmModeSetCursor2
.hidden real_drmMsg
.global drmMsg
.type drmMsg, @function
drmMsg:
  movq real_drmMsg(%rip), %rax
  jmp *%rax
.size drmMsg, .-drmMsg
.hidden real_drmOpen
.global drmOpen
.type drmOpen, @function
drmOpen:
  movq real_drmOpen(%rip), %rax
  jmp *%rax
.size drmOpen, .-drmOpen
.hidden real_drmOpenControl
.global drmOpenControl
.type drmOpenControl, @function
drmOpenControl:
  movq real_drmOpenControl(%rip), %rax
  jmp *%rax
.size drmOpenControl, .-drmOpenControl
.hidden real_drmOpenOnce
.global drmOpenOnce
.type drmOpenOnce, @function
drmOpenOnce:
  movq real_drmOpenOnce(%rip), %rax
  jmp *%rax
.size drmOpenOnce, .-drmOpenOnce
.hidden real_drmOpenOnceWithType
.global drmOpenOnceWithType
.type drmOpenOnceWithType, @function
drmOpenOnceWithType:
  movq real_drmOpenOnceWithType(%rip), %rax
  jmp *%rax
.size drmOpenOnceWithType, .-drmOpenOnceWithType
.hidden real_drmOpenRender
.global drmOpenRender
.type drmOpenRender, @function
drmOpenRender:
  movq real_drmOpenRender(%rip), %rax
  jmp *%rax
.size drmOpenRender, .-drmOpenRender
.hidden real_drmOpenWithType
.global drmOpenWithType
.type drmOpenWithType, @function
drmOpenWithType:
  movq real_drmOpenWithType(%rip), %rax
  jmp *%rax
.size drmOpenWithType, .-drmOpenWithType
.hidden real_drmPrimeFDToHandle
.global drmPrimeFDToHandle
.type drmPrimeFDToHandle, @function
drmPrimeFDToHandle:
  movq real_drmPrimeFDToHandle(%rip), %rax
  jmp *%rax
.size drmPrimeFDToHandle, .-drmPrimeFDToHandle
.hidden real_drmPrimeHandleToFD
.global drmPrimeHandleToFD
.type drmPrimeHandleToFD, @function
drmPrimeHandleToFD:
  movq real_drmPrimeHandleToFD(%rip), %rax
  jmp *%rax
.size drmPrimeHandleToFD, .-drmPrimeHandleToFD
.hidden real_drmRandom
.global drmRandom
.type drmRandom, @function
drmRandom:
  movq real_drmRandom(%rip), %rax
  jmp *%rax
.size drmRandom, .-drmRandom
.hidden real_drmRandomCreate
.global drmRandomCreate
.type drmRandomCreate, @function
drmRandomCreate:
  movq real_drmRandomCreate(%rip), %rax
  jmp *%rax
.size drmRandomCreate, .-drmRandomCreate
.hidden real_drmRandomDestroy
.global drmRandomDestroy
.type drmRandomDestroy, @function
drmRandomDestroy:
  movq real_drmRandomDestroy(%rip), %rax
  jmp *%rax
.size drmRandomDestroy, .-drmRandomDestroy
.hidden real_drmRandomDouble
.global drmRandomDouble
.type drmRandomDouble, @function
drmRandomDouble:
  movq real_drmRandomDouble(%rip), %rax
  jmp *%rax
.size drmRandomDouble, .-drmRandomDouble
.hidden real_drmRmMap
.global drmRmMap
.type drmRmMap, @function
drmRmMap:
  movq real_drmRmMap(%rip), %rax
  jmp *%rax
.size drmRmMap, .-drmRmMap
.hidden real_drmScatterGatherAlloc
.global drmScatterGatherAlloc
.type drmScatterGatherAlloc, @function
drmScatterGatherAlloc:
  movq real_drmScatterGatherAlloc(%rip), %rax
  jmp *%rax
.size drmScatterGatherAlloc, .-drmScatterGatherAlloc
.hidden real_drmScatterGatherFree
.global drmScatterGatherFree
.type drmScatterGatherFree, @function
drmScatterGatherFree:
  movq real_drmScatterGatherFree(%rip), %rax
  jmp *%rax
.size drmScatterGatherFree, .-drmScatterGatherFree
.hidden real_drmSetBusid
.global drmSetBusid
.type drmSetBusid, @function
drmSetBusid:
  movq real_drmSetBusid(%rip), %rax
  jmp *%rax
.size drmSetBusid, .-drmSetBusid
.hidden real_drmSetClientCap
.global drmSetClientCap
.type drmSetClientCap, @function
drmSetClientCap:
  movq real_drmSetClientCap(%rip), %rax
  jmp *%rax
.size drmSetClientCap, .-drmSetClientCap
.hidden real_drmSetContextFlags
.global drmSetContextFlags
.type drmSetContextFlags, @function
drmSetContextFlags:
  movq real_drmSetContextFlags(%rip), %rax
  jmp *%rax
.size drmSetContextFlags, .-drmSetContextFlags
.hidden real_drmSetInterfaceVersion
.global drmSetInterfaceVersion
.type drmSetInterfaceVersion, @function
drmSetInterfaceVersion:
  movq real_drmSetInterfaceVersion(%rip), %rax
  jmp *%rax
.size drmSetInterfaceVersion, .-drmSetInterfaceVersion
.hidden real_drmSetMaster
.global drmSetMaster
.type drmSetMaster, @function
drmSetMaster:
  movq real_drmSetMaster(%rip), %rax
  jmp *%rax
.size drmSetMaster, .-drmSetMaster
.hidden real_drmSetServerInfo
.global drmSetServerInfo
.type drmSetServerInfo, @function
drmSetServerInfo:
  movq real_drmSetServerInfo(%rip), %rax
  jmp *%rax
.size drmSetServerInfo, .-drmSetServerInfo
.hidden real_drmSLCreate
.global drmSLCreate
.type drmSLCreate, @function
drmSLCreate:
  movq real_drmSLCreate(%rip), %rax
  jmp *%rax
.size drmSLCreate, .-drmSLCreate
.hidden real_drmSLDelete
.global drmSLDelete
.type drmSLDelete, @function
drmSLDelete:
  movq real_drmSLDelete(%rip), %rax
  jmp *%rax
.size drmSLDelete, .-drmSLDelete
.hidden real_drmSLDestroy
.global drmSLDestroy
.type drmSLDestroy, @function
drmSLDestroy:
  movq real_drmSLDestroy(%rip), %rax
  jmp *%rax
.size drmSLDestroy, .-drmSLDestroy
.hidden real_drmSLDump
.global drmSLDump
.type drmSLDump, @function
drmSLDump:
  movq real_drmSLDump(%rip), %rax
  jmp *%rax
.size drmSLDump, .-drmSLDump
.hidden real_drmSLFirst
.global drmSLFirst
.type drmSLFirst, @function
drmSLFirst:
  movq real_drmSLFirst(%rip), %rax
  jmp *%rax
.size drmSLFirst, .-drmSLFirst
.hidden real_drmSLInsert
.global drmSLInsert
.type drmSLInsert, @function
drmSLInsert:
  movq real_drmSLInsert(%rip), %rax
  jmp *%rax
.size drmSLInsert, .-drmSLInsert
.hidden real_drmSLLookup
.global drmSLLookup
.type drmSLLookup, @function
drmSLLookup:
  movq real_drmSLLookup(%rip), %rax
  jmp *%rax
.size drmSLLookup, .-drmSLLookup
.hidden real_drmSLLookupNeighbors
.global drmSLLookupNeighbors
.type drmSLLookupNeighbors, @function
drmSLLookupNeighbors:
  movq real_drmSLLookupNeighbors(%rip), %rax
  jmp *%rax
.size drmSLLookupNeighbors, .-drmSLLookupNeighbors
.hidden real_drmSLNext
.global drmSLNext
.type drmSLNext, @function
drmSLNext:
  movq real_drmSLNext(%rip), %rax
  jmp *%rax
.size drmSLNext, .-drmSLNext
.hidden real_drmSwitchToContext
.global drmSwitchToContext
.type drmSwitchToContext, @function
drmSwitchToContext:
  movq real_drmSwitchToContext(%rip), %rax
  jmp *%rax
.size drmSwitchToContext, .-drmSwitchToContext
.hidden real_drmSyncobjCreate
.global drmSyncobjCreate
.type drmSyncobjCreate, @function
drmSyncobjCreate:
  movq real_drmSyncobjCreate(%rip), %rax
  jmp *%rax
.size drmSyncobjCreate, .-drmSyncobjCreate
.hidden real_drmSyncobjDestroy
.global drmSyncobjDestroy
.type drmSyncobjDestroy, @function
drmSyncobjDestroy:
  movq real_drmSyncobjDestroy(%rip), %rax
  jmp *%rax
.size drmSyncobjDestroy, .-drmSyncobjDestroy
.hidden real_drmSyncobjEventfd
.global drmSyncobjEventfd
.type drmSyncobjEventfd, @function
drmSyncobjEventfd:
  movq real_drmSyncobjEventfd(%rip), %rax
  jmp *%rax
.size drmSyncobjEventfd, .-drmSyncobjEventfd
.hidden real_drmSyncobjExportSyncFile
.global drmSyncobjExportSyncFile
.type drmSyncobjExportSyncFile, @function
drmSyncobjExportSyncFile:
  movq real_drmSyncobjExportSyncFile(%rip), %rax
  jmp *%rax
.size drmSyncobjExportSyncFile, .-drmSyncobjExportSyncFile
.hidden real_drmSyncobjFDToHandle
.global drmSyncobjFDToHandle
.type drmSyncobjFDToHandle, @function
drmSyncobjFDToHandle:
  movq real_drmSyncobjFDToHandle(%rip), %rax
  jmp *%rax
.size drmSyncobjFDToHandle, .-drmSyncobjFDToHandle
.hidden real_drmSyncobjHandleToFD
.global drmSyncobjHandleToFD
.type drmSyncobjHandleToFD, @function
drmSyncobjHandleToFD:
  movq real_drmSyncobjHandleToFD(%rip), %rax
  jmp *%rax
.size drmSyncobjHandleToFD, .-drmSyncobjHandleToFD
.hidden real_drmSyncobjImportSyncFile
.global drmSyncobjImportSyncFile
.type drmSyncobjImportSyncFile, @function
drmSyncobjImportSyncFile:
  movq real_drmSyncobjImportSyncFile(%rip), %rax
  jmp *%rax
.size drmSyncobjImportSyncFile, .-drmSyncobjImportSyncFile
.hidden real_drmSyncobjQuery
.global drmSyncobjQuery
.type drmSyncobjQuery, @function
drmSyncobjQuery:
  movq real_drmSyncobjQuery(%rip), %rax
  jmp *%rax
.size drmSyncobjQuery, .-drmSyncobjQuery
.hidden real_drmSyncobjQuery2
.global drmSyncobjQuery2
.type drmSyncobjQuery2, @function
drmSyncobjQuery2:
  movq real_drmSyncobjQuery2(%rip), %rax
  jmp *%rax
.size drmSyncobjQuery2, .-drmSyncobjQuery2
.hidden real_drmSyncobjReset
.global drmSyncobjReset
.type drmSyncobjReset, @function
drmSyncobjReset:
  movq real_drmSyncobjReset(%rip), %rax
  jmp *%rax
.size drmSyncobjReset, .-drmSyncobjReset
.hidden real_drmSyncobjSignal
.global drmSyncobjSignal
.type drmSyncobjSignal, @function
drmSyncobjSignal:
  movq real_drmSyncobjSignal(%rip), %rax
  jmp *%rax
.size drmSyncobjSignal, .-drmSyncobjSignal
.hidden real_drmSyncobjTimelineSignal
.global drmSyncobjTimelineSignal
.type drmSyncobjTimelineSignal, @function
drmSyncobjTimelineSignal:
  movq real_drmSyncobjTimelineSignal(%rip), %rax
  jmp *%rax
.size drmSyncobjTimelineSignal, .-drmSyncobjTimelineSignal
.hidden real_drmSyncobjTimelineWait
.global drmSyncobjTimelineWait
.type drmSyncobjTimelineWait, @function
drmSyncobjTimelineWait:
  movq real_drmSyncobjTimelineWait(%rip), %rax
  jmp *%rax
.size drmSyncobjTimelineWait, .-drmSyncobjTimelineWait
.hidden real_drmSyncobjTransfer
.global drmSyncobjTransfer
.type drmSyncobjTransfer, @function
drmSyncobjTransfer:
  movq real_drmSyncobjTransfer(%rip), %rax
  jmp *%rax
.size drmSyncobjTransfer, .-drmSyncobjTransfer
.hidden real_drmSyncobjWait
.global drmSyncobjWait
.type drmSyncobjWait, @function
drmSyncobjWait:
  movq real_drmSyncobjWait(%rip), %rax
  jmp *%rax
.size drmSyncobjWait, .-drmSyncobjWait
.hidden real_drmUnlock
.global drmUnlock
.type drmUnlock, @function
drmUnlock:
  movq real_drmUnlock(%rip), %rax
  jmp *%rax
.size drmUnlock, .-drmUnlock
.hidden real_drmUnmap
.global drmUnmap
.type drmUnmap, @function
drmUnmap:
  movq real_drmUnmap(%rip), %rax
  jmp *%rax
.size drmUnmap, .-drmUnmap
.hidden real_drmUnmapBufs
.global drmUnmapBufs
.type drmUnmapBufs, @function
drmUnmapBufs:
  movq real_drmUnmapBufs(%rip), %rax
  jmp *%rax
.size drmUnmapBufs, .-drmUnmapBufs
.hidden real_drmUpdateDrawableInfo
.global drmUpdateDrawableInfo
.type drmUpdateDrawableInfo, @function
drmUpdateDrawableInfo:
  movq real_drmUpdateDrawableInfo(%rip), %rax
  jmp *%rax
.size drmUpdateDrawableInfo, .-drmUpdateDrawableInfo
.hidden real_drmWaitVBlank
.global drmWaitVBlank
.type drmWaitVBlank, @function
drmWaitVBlank:
  movq real_drmWaitVBlank(%rip), %rax
  jmp *%rax
.size drmWaitVBlank, .-drmWaitVBlank
