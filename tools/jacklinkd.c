/*
 * jacklinkd.c -- restore JACK/PipeWire links after an audio device replug.
 *
 * ENCORE runs Ableton Live's audio through WineASIO -> PipeWire's JACK server.
 * Live's ASIO "device" is really the JACK graph, which survives a hardware
 * unplug -- but the *links* between WineASIO's ports and the hardware ports are
 * destroyed with the device node, and neither PipeWire nor WirePlumber restores
 * JACK links on replug (their restore logic covers pulse/native streams only).
 * The result: Live goes silent after an interface is unplugged and plugged back
 * in, until its audio engine is restarted.
 *
 * This daemon is a port-less JACK client that watches the graph and re-creates
 * links that were lost to a device disappearing. A link is only remembered for
 * restoration if the port carrying it unregistered shortly after the link went
 * away -- so a deliberate `jack_disconnect` / patchbay edit is left alone. It
 * restores only links it has actually observed; like the winealsa MIDI hotplug
 * fix it cannot invent routing for a device that was never wired up.
 *
 * The approach (device-death graveyard keyed by port name; restore on
 * reappearance) is adapted from shibco/ableton-linux's jacklinkd; this is an
 * independent reimplementation for ENCORE. JACK forbids calling graph-mutating
 * functions from a notification callback, so callbacks here only update bookkeeping
 * under a mutex and wake the main thread, which is the sole caller of jack_connect.
 *
 * build: cc -O2 -o jacklinkd jacklinkd.c -ljack -lpthread
 * run:   started by run-ableton.sh; also safe to run on its own.
 */
#include <jack/jack.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

enum {
    PORT_NAME_MAX = 256,
    MAX_LINKS     = 512,   /* links currently up */
    MAX_PENDING   = 256,   /* links awaiting a replug */
    MAX_TORN      = 128,   /* links just torn down, still deciding why */
    DEATH_WINDOW_MS = 5000 /* teardown->unregister gap that means "device died" */
};

struct edge {
    char from[PORT_NAME_MAX];
    char to[PORT_NAME_MAX];
};

struct torn_edge {
    struct edge e;
    uint64_t when_ms;
};

static jack_client_t *jack;

static pthread_mutex_t state_mtx = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  restore_cv = PTHREAD_COND_INITIALIZER;
static int restore_pending;
static int stopping;

static struct edge      up[MAX_LINKS];       int n_up;
static struct torn_edge torn[MAX_TORN];      int n_torn;
static struct edge      pending[MAX_PENDING]; int n_pending;

static uint64_t monotonic_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

static int edge_eq(const struct edge *a, const struct edge *b)
{
    return !strcmp(a->from, b->from) && !strcmp(a->to, b->to);
}

static int edge_touches(const struct edge *e, const char *port)
{
    return !strcmp(e->from, port) || !strcmp(e->to, port);
}

static void set_edge(struct edge *e, const char *from, const char *to)
{
    snprintf(e->from, PORT_NAME_MAX, "%s", from);
    snprintf(e->to, PORT_NAME_MAX, "%s", to);
}

/* drop pending[i] whether or not it is worth keeping */
static void drop_pending(int i)
{
    pending[i] = pending[--n_pending];
}

static void remember_for_restore(const struct edge *e)
{
    int i;
    for (i = 0; i < n_pending; i++)
        if (edge_eq(&pending[i], e))
            return;
    if (n_pending >= MAX_PENDING)
        return;
    pending[n_pending++] = *e;
    fprintf(stderr, "jacklinkd: will restore %s -> %s\n", e->from, e->to);
}

/* --- JACK notification callbacks: bookkeeping only, never touch the graph --- */

static void on_port_connect(jack_port_id_t a, jack_port_id_t b, int connected, void *arg)
{
    jack_port_t *pa = jack_port_by_id(jack, a);
    jack_port_t *pb = jack_port_by_id(jack, b);
    struct edge e;
    int i;

    (void)arg;
    if (!pa || !pb)
        return;
    set_edge(&e, jack_port_name(pa), jack_port_name(pb));

    pthread_mutex_lock(&state_mtx);
    if (connected) {
        for (i = 0; i < n_up; i++)
            if (edge_eq(&up[i], &e))
                break;
        if (i == n_up && n_up < MAX_LINKS)
            up[n_up++] = e;
        /* a fresh (re)connect satisfies any pending restore for this edge */
        for (i = 0; i < n_pending; i++)
            if (edge_eq(&pending[i], &e)) { drop_pending(i); i--; }
    } else {
        for (i = 0; i < n_up; i++)
            if (edge_eq(&up[i], &e)) { up[i] = up[--n_up]; break; }
        if (n_torn < MAX_TORN) {
            torn[n_torn].e = e;
            torn[n_torn].when_ms = monotonic_ms();
            n_torn++;
        }
    }
    pthread_mutex_unlock(&state_mtx);
}

static void on_port_registration(jack_port_id_t id, int registered, void *arg)
{
    jack_port_t *p = jack_port_by_id(jack, id);
    const char *name;
    uint64_t now = monotonic_ms();
    int i;

    (void)arg;
    if (!p)
        return;
    name = jack_port_name(p);

    pthread_mutex_lock(&state_mtx);
    if (!registered) {
        /* Port vanished. Any link it carried that was torn down within the
         * death window is device loss, not a user disconnect -- remember it. */
        for (i = 0; i < n_torn; i++) {
            if (now - torn[i].when_ms > DEATH_WINDOW_MS || !edge_touches(&torn[i].e, name))
                continue;
            remember_for_restore(&torn[i].e);
            torn[i] = torn[--n_torn];
            i--;
        }
        /* Some teardowns arrive only as the unregister (no disconnect event). */
        for (i = 0; i < n_up; i++) {
            if (!edge_touches(&up[i], name))
                continue;
            remember_for_restore(&up[i]);
            up[i] = up[--n_up];
            i--;
        }
    } else {
        for (i = 0; i < n_pending; i++)
            if (edge_touches(&pending[i], name)) {
                restore_pending = 1;
                pthread_cond_signal(&restore_cv);
                break;
            }
    }
    pthread_mutex_unlock(&state_mtx);
}

static void on_shutdown(void *arg)
{
    (void)arg;
    pthread_mutex_lock(&state_mtx);
    stopping = 1;
    restore_pending = 1;
    pthread_cond_signal(&restore_cv);
    pthread_mutex_unlock(&state_mtx);
}

/* --- main thread: the only place that mutates the graph --- */

static void restore_now(void)
{
    struct edge todo[MAX_PENDING];
    int n, i;

    pthread_mutex_lock(&state_mtx);
    n = n_pending;
    for (i = 0; i < n; i++)
        todo[i] = pending[i];
    pthread_mutex_unlock(&state_mtx);

    for (i = 0; i < n; i++) {
        /* Wait until both ends exist; a later registration wakes us to retry. */
        if (!jack_port_by_name(jack, todo[i].from) || !jack_port_by_name(jack, todo[i].to))
            continue;
        if (jack_connect(jack, todo[i].from, todo[i].to) == 0)
            fprintf(stderr, "jacklinkd: restored %s -> %s\n", todo[i].from, todo[i].to);
        /* on success (or EEXIST) on_port_connect() clears the pending entry */
    }
}

/* record the links already present when we attach, so a later device death
 * still knows what to put back */
static void seed_existing_links(void)
{
    const char **outs = jack_get_ports(jack, NULL, NULL, JackPortIsOutput);
    int i, j;

    if (!outs)
        return;
    pthread_mutex_lock(&state_mtx);
    for (i = 0; outs[i] && n_up < MAX_LINKS; i++) {
        jack_port_t *p = jack_port_by_name(jack, outs[i]);
        const char **peers = p ? jack_port_get_all_connections(jack, p) : NULL;
        if (!peers)
            continue;
        for (j = 0; peers[j] && n_up < MAX_LINKS; j++)
            set_edge(&up[n_up++], outs[i], peers[j]);
        jack_free((void *)peers);
    }
    pthread_mutex_unlock(&state_mtx);
    jack_free((void *)outs);
}

int main(void)
{
    for (;;) {
        jack = jack_client_open("encore-jacklinkd", JackNoStartServer, NULL);
        if (!jack) {
            sleep(2); /* JACK/PipeWire not up yet; keep trying */
            continue;
        }

        pthread_mutex_lock(&state_mtx);
        stopping = 0;
        n_up = 0;
        n_torn = 0;
        /* the pending graveyard deliberately survives a server restart */
        pthread_mutex_unlock(&state_mtx);

        jack_set_port_connect_callback(jack, on_port_connect, NULL);
        jack_set_port_registration_callback(jack, on_port_registration, NULL);
        jack_on_shutdown(jack, on_shutdown, NULL);

        if (jack_activate(jack) != 0) {
            jack_client_close(jack);
            sleep(2);
            continue;
        }
        seed_existing_links();
        fprintf(stderr, "jacklinkd: watching the JACK graph\n");

        for (;;) {
            pthread_mutex_lock(&state_mtx);
            while (!restore_pending)
                pthread_cond_wait(&restore_cv, &state_mtx);
            restore_pending = 0;
            if (stopping) {
                pthread_mutex_unlock(&state_mtx);
                break;
            }
            pthread_mutex_unlock(&state_mtx);

            usleep(300000); /* let a reappearing device's ports settle */
            restore_now();
        }

        jack_client_close(jack);
        sleep(2);
    }
    return 0;
}
