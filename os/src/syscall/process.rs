//! Process management syscalls
use crate::{
    task::{exit_current_and_run_next, suspend_current_and_run_next,get_current_task},
    timer::get_time_us,
    sync::UPSafeCell,


    
};
use core::ptr::{read_volatile,write_volatile};
use lazy_static::lazy_static;

#[repr(C)]
#[derive(Debug)]
pub struct TimeVal {
    pub sec: usize,
    pub usec: usize,
}

const SYSCALL_MAX: usize = 512;
const TASK_MAX:usize=16;
lazy_static!{
    static ref SYSCALL_COUNTER: UPSafeCell<[[usize;SYSCALL_MAX]; TASK_MAX]> =
    unsafe { UPSafeCell::new([[0; SYSCALL_MAX];TASK_MAX]) };
}
/// 增加调用计数
pub fn incr_syscall(s_id: usize,t_id:usize) {
    let mut counter = SYSCALL_COUNTER.exclusive_access();
    counter[t_id][s_id] += 1;
}

/// 查询调用次数
fn get_syscall_count(s_id: usize,t_id:usize) -> usize {
    let counter = SYSCALL_COUNTER.exclusive_access();
    counter[t_id][s_id]
}

/// task exits and submit an exit code
pub fn sys_exit(exit_code: i32) -> ! {
    trace!("[kernel] Application exited with code {}", exit_code);
    exit_current_and_run_next();
    panic!("Unreachable in sys_exit!");
}

/// current task gives up resources for other tasks
pub fn sys_yield() -> isize {
    trace!("kernel: sys_yield");
    suspend_current_and_run_next();
    0
}

/// get time with second and microsecond
pub fn sys_get_time(ts: *mut TimeVal, _tz: usize) -> isize {
    trace!("kernel: sys_get_time");
    let us = get_time_us();
    unsafe {
        *ts = TimeVal {
            sec: us / 1_000_000,
            usec: us % 1_000_000,
        };
    }
    0
}

// TODO: implement the syscall
pub fn sys_trace(trace_request: usize, id: usize, data: usize) -> isize {
    trace!("kernel: sys_trace");
    match trace_request {
        0 => {
            let ptr=id as *const u8;
            unsafe{read_volatile(ptr)as isize}
        }
        1 => {
            
            let to_write = data as u8;
            let ptr_cell=unsafe{UPSafeCell::new(id as *mut u8)};
            let ptr=ptr_cell.exclusive_access();
            unsafe{write_volatile(*ptr,to_write);}
            0
        }
        2 => {
            let current=get_current_task();
            get_syscall_count(id,current)as isize
        },

        _ => -1,
    }
}
