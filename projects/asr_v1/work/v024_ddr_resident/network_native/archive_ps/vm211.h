#ifndef VM211_H
#define VM211_H
#include "resident.h"
int vm211_run(const struct v10_io *,uint32_t address,uint32_t reply[16]);
void vm211_status(uint32_t reply[64]);
#endif
