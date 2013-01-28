(** The In_thread module has functions for interaction between the Async world and other
    (kernel) threads.  The name is to remind us to think about threads and race
    conditions. *)

open Core.Std
open Async_core

module Priority : module type of Linux_ext.Priority with type t = Linux_ext.Priority.t

module Helper_thread : sig
  (** A Helper_thread is a thread that is dedicated to handling computations external to
      Async.  We need them because some libraries (e.g. Sqlite3) require that certain
      collections of computations run in the same thread. *)
  type t

  (* [create ?name ()] creates a new helper thread.  The [name] will be used as the thread
     name for any work that that is done by the thread that doesn't get its own name. *)
  val create : ?priority:Priority.t -> ?name:string -> unit -> t Or_error.t
end

(** [pipe_of_squeue squeue] returns a pipe [p] and consumes the contents [squeue], placing
    them in [p].  It repeatedly grabs everything from [squeue], places it in [p], and
    then waits for pushback on [p]. *)
val pipe_of_squeue : 'a Squeue.t -> 'a Pipe.Reader.t

(** [run ?priority ?thread ?name f] runs [f()] in another thread and returns the result as a
    Deferred in the Async world.  If [f()] raises an exception (asynchronously, since it
    is another thread) then that exception will be raised to the monitor that called
    [run()].

    Async code should not be used from within [f].

    If [thread] is not supplied, then any thread from the thread pool could be used.  If
    you need to run routines in a specific thread (as is required by some libraries like
    Sqlite), you should create a helper thread and supply it to [run].

    If [priority] is supplied, the priority of the thread in the linux scheduler will be
    set to [priority] for the duration of [f()], provided the thread is allowed to do so,
    see `man setpriority`.

    If you call [run] several times with the same helper thread, the [f()] calls will run
    in sequence, in the order in which they are supplied to [run].  Each [f()] will
    complete (return or raise) before another [f()] starts.

    For example, if you call:

    [run ~thread f1]
    [run ~thread f2]
    [run ~thread f3]

    Then the thread will run [f1 ()] to completion, then [f2 ()] to completion, then
    [f3 ()] to completion.

    If [name] is supplied, the name of the thread will be set to it for the duration of
    the execution of [f ()]. *)
val run
  :  ?priority:Priority.t
  -> ?thread:Helper_thread.t
  -> ?name:string
  -> (unit -> 'a)
  -> 'a Deferred.t

(** [syscall f] runs f, which should be a single system call, and returns the result,
    handling the restarting of interrupted system calls.  To avoid race conditions, the
    [f] supplied to [syscall] should just make a system call.  That way, everything else
    is done holding the Async lock. *)
val syscall     : name:string -> (unit -> 'a) -> ('a, exn) Result.t Deferred.t
val syscall_exn : name:string -> (unit -> 'a) ->  'a                Deferred.t
