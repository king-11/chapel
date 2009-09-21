// MTA implementation

#include "chplrt.h"
#include "chplthreads.h"
#include "chpl_mem.h"
#include "error.h"
#include <stdlib.h>
#include <stdint.h>
#include <machine/runtime.h>


// The global vars are to synchronize with threads created with 
// begin's which are not joined.  We need to wait on them before the
// main thread can call exit for the process.
static int64_t          chpl_begin_cnt;      // number of unjoined threads 
static sync int64_t     chpl_can_exit;       // can main thread exit?


// Mutex

void chpl_mutex_init(chpl_mutex_p mutex) {
  purge(mutex);                     // set to zero and mark empty
}

void chpl_mutex_lock(chpl_mutex_p mutex) {
  writeef(mutex, 1);                // set to one and mark full
}

void chpl_mutex_unlock(chpl_mutex_p mutex) {
  chpl_mutex_init(mutex);
}


// Sync variables

void chpl_sync_lock(chpl_sync_aux_t *s) {
  readfe(&(s->is_full));            // mark empty
}

void chpl_sync_unlock(chpl_sync_aux_t *s) {
  int64_t is_full = readxx(&(s->is_full));
  writeef(&(s->is_full), is_full);  // mark full
}

void chpl_sync_wait_full_and_lock(chpl_sync_aux_t *s, int32_t lineno, chpl_string filename) {
  chpl_sync_lock(s);
  while (!readxx(&(s->is_full))) {
    chpl_sync_unlock(s);
    readfe(&(s->signal_full));
    chpl_sync_lock(s);
  }
}

void chpl_sync_wait_empty_and_lock(chpl_sync_aux_t *s, int32_t lineno, chpl_string filename) {
  chpl_sync_lock(s);
  while (readxx(&(s->is_full))) {
    chpl_sync_unlock(s);
    readfe(&(s->signal_empty));
    chpl_sync_lock(s);
  }
}

void chpl_sync_mark_and_signal_full(chpl_sync_aux_t *s) {
  writexf(&(s->signal_full), true);                // signal full
  writeef(&(s->is_full), true);                    // mark full and unlock
}

void chpl_sync_mark_and_signal_empty(chpl_sync_aux_t *s) {
  writexf(&(s->signal_empty), true);               // signal empty
  writeef(&(s->is_full), false);                   // mark empty and unlock
}

chpl_bool chpl_sync_is_full(void *val_ptr, chpl_sync_aux_t *s, chpl_bool simple_sync_var) {
  if (simple_sync_var)
    return (chpl_bool)(((unsigned)MTA_STATE_LOAD(val_ptr)<<3)>>63 == 0);
  else
    return (chpl_bool)readxx(&(s->is_full));
}

void chpl_init_sync_aux(chpl_sync_aux_t *s) {
  writexf(&(s->is_full), 0);          // mark empty and unlock
  purge(&(s->signal_empty));
  purge(&(s->signal_full));
}

void chpl_destroy_sync_aux(chpl_sync_aux_t *s) { }


// Single variables

void chpl_single_lock(chpl_single_aux_t *s) {
  readfe(&(s->is_full));            // mark empty
}

void chpl_single_unlock(chpl_single_aux_t *s) {
  int64_t is_full = readxx(&(s->is_full));
  writeef(&(s->is_full), is_full);  // mark full
}

void chpl_single_wait_full(chpl_single_aux_t *s, int32_t lineno, chpl_string filename) {
  while (!readxx(&(s->is_full)))
    readff(&(s->signal_full));
}

void chpl_single_mark_and_signal_full(chpl_single_aux_t *s) {
  writexf(&(s->is_full), true);     // mark full and unlock
  writexf(&(s->signal_full), true); // signal full
}

chpl_bool chpl_single_is_full(void *val_ptr, chpl_single_aux_t *s, chpl_bool simple_single_var) {
  if (simple_single_var)
    return (chpl_bool)(((unsigned)MTA_STATE_LOAD(val_ptr)<<3)>>63 == 0);
  else
    return (chpl_bool)readxx(&(s->is_full));
}

void chpl_init_single_aux(chpl_single_aux_t *s) {
  writexf(&(s->is_full), 0);          // mark empty and unlock
  purge(&(s->signal_full));
}

void chpl_destroy_single_aux(chpl_single_aux_t *s) { }

// Tasks

void chpl_tasking_init() {
  chpl_begin_cnt = 0;                     // only main thread running
  chpl_can_exit = 1;                      // mark full - no threads created yet
}

void chpl_tasking_exit() {
  int ready=0;
  do
    // this will block until chpl_can_exit is marked full!
    ready = readff(&chpl_can_exit);
  while (!ready);
}

void chpl_add_to_task_list(chpl_fn_int_t fid,
                           void* arg,
                           chpl_task_list_p *task_list,
                           int32_t task_list_locale,
                           chpl_bool call_chpl_begin,
                           int lineno,
                           chpl_string filename) {
  chpl_begin(chpl_ftable[fid], arg, false, false, NULL);
}

void chpl_process_task_list (chpl_task_list_p task_list) { }

void chpl_execute_tasks_in_list (chpl_task_list_p task_list) { }

void chpl_free_task_list (chpl_task_list_p task_list) { }

void
chpl_begin (chpl_fn_p fp, void* arg, chpl_bool ignore_serial, 
            chpl_bool serial_state, chpl_task_list_p task_list_entry) {

  if (!ignore_serial && chpl_get_serial())
    (*fp)(arg);

  else {
    int init_begin_cnt =
      int_fetch_add(&chpl_begin_cnt, 1);       // assume begin will succeed
    purge(&chpl_can_exit);                     // set to zero and mark as empty

    // Will call the real begin statement function. Only purpose of this
    // thread is to wait on that function and coordinate the exiting
    // of the main Chapel thread.
    future (fp, arg, init_begin_cnt) {
      int64_t         begin_cnt;

      (*fp)(arg);

      // decrement begin thread count and see if we can signal Chapel exit
      begin_cnt = int_fetch_add(&chpl_begin_cnt, -1);
      if (begin_cnt == 1)   // i.e., chpl_begin_cnt is now zero
        chpl_can_exit = 1; // mark this variable as being full
    }
  }
}

chpl_bool chpl_get_serial(void) {
  chpl_bool *p = NULL;
  p = (chpl_bool*) mta_register_task_data(p);
  if (p == NULL)
    return false;
  else {
    mta_register_task_data(p); // Put back the value retrieved above.
    return *p;
  }
}

void chpl_set_serial(chpl_bool state) {
  chpl_bool *p = NULL;
  p = (chpl_bool*) mta_register_task_data(p);
  if (p == NULL)
    p = (chpl_bool*) chpl_alloc(sizeof(chpl_bool), CHPL_RT_MD_SERIAL_FLAG, 0, 0);
  if (p) {
    *p = state;
    mta_register_task_data(p);
  } else
    chpl_internal_error("out of memory while creating serial state");
}

// not sure what the correct value should be here!
uint32_t chpl_numQueuedTasks(void) { return 0; }

// not sure what the correct value should be here!
uint32_t chpl_numRunningTasks(void) { return 1; }

// not sure what the correct value should be here!
int32_t  chpl_numBlockedTasks(void) { return -1; }


// Threads

chpl_threadID_t chpl_thread_id(void) {
  return (chpl_threadID_t) mta_get_threadid(); 
}

void chpl_thread_cancel(chpl_threadID_t threadID) {
  chpl_internal_error("chpl_thread_cancel() shouldn't be called in threads-mta");
}

void chpl_thread_join(chpl_threadID_t threadID) {
  chpl_internal_error("chpl_thread_join() shouldn't be called in threads-mta");
}

int32_t chpl_threads_getMaxThreads(void) {
  return chpl_coresPerLocale() * 100;
}

int32_t chpl_threads_maxThreadsLimit(void) {
  return chpl_coresPerLocale() * 104;
}

// not sure what the correct value should be here!
uint32_t chpl_numThreads(void) { return 1; }

// not sure what the correct value should be here!
uint32_t chpl_numIdleThreads(void) { return 0; }
