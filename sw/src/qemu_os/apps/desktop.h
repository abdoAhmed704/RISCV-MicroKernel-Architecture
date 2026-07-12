/*
 * desktop.h — Desktop application public interface
 */
#ifndef DESKTOP_H
#define DESKTOP_H

/**
 * desktop_run() — Initialise all desktop windows and enter the
 * main event loop.  This function never returns under normal OS
 * operation; the OS shuts down when the user presses Q.
 */
void desktop_run(void);

#endif /* DESKTOP_H */
