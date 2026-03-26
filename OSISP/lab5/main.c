#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    int *arr;
    size_t left;
    size_t right;
} sort_task_t;

static int int_cmp(const void *a, const void *b) {
    int lhs = *(const int *)a;
    int rhs = *(const int *)b;
    if (lhs < rhs) {
        return -1;
    }
    if (lhs > rhs) {
        return 1;
    }
    return 0;
}

static void *thread_sort(void *arg) {
    sort_task_t *task = (sort_task_t *)arg;
    qsort(task->arr + task->left, task->right - task->left, sizeof(int), int_cmp);
    return NULL;
}

static uint64_t elapsed_ms(const struct timespec *start, const struct timespec *end) {
    uint64_t sec = (uint64_t)(end->tv_sec - start->tv_sec);
    int64_t nsec = end->tv_nsec - start->tv_nsec;
    if (nsec < 0) {
        sec--;
        nsec += 1000000000LL;
    }
    return sec * 1000ULL + (uint64_t)(nsec / 1000000LL);
}

static int is_sorted(const int *arr, size_t n) {
    for (size_t i = 1; i < n; ++i) {
        if (arr[i - 1] > arr[i]) {
            return 0;
        }
    }
    return 1;
}

static int merge_sorted_chunks(const int *src, int *dst, const size_t *starts, const size_t *ends, size_t chunks) {
    size_t *idx = calloc(chunks, sizeof(size_t));
    if (idx == NULL) {
        return -1;
    }

    for (size_t c = 0; c < chunks; ++c) {
        idx[c] = starts[c];
    }

    size_t out = 0;
    while (1) {
        size_t min_chunk = SIZE_MAX;
        int min_value = 0;

        for (size_t c = 0; c < chunks; ++c) {
            if (idx[c] >= ends[c]) {
                continue;
            }
            int candidate = src[idx[c]];
            if (min_chunk == SIZE_MAX || candidate < min_value) {
                min_chunk = c;
                min_value = candidate;
            }
        }

        if (min_chunk == SIZE_MAX) {
            break;
        }

        dst[out++] = min_value;
        idx[min_chunk]++;
    }

    free(idx);
    return 0;
}

static void fill_random(int *arr, size_t n, unsigned int seed) {
    srand(seed);
    for (size_t i = 0; i < n; ++i) {
        arr[i] = rand();
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <array_size> <threads_count>\n", argv[0]);
        return 1;
    }

    errno = 0;
    char *end_n = NULL;
    unsigned long n_ul = strtoul(argv[1], &end_n, 10);
    if (errno != 0 || end_n == argv[1] || *end_n != '\0' || n_ul == 0) {
        fprintf(stderr, "Invalid array_size: %s\n", argv[1]);
        return 1;
    }

    errno = 0;
    char *end_t = NULL;
    unsigned long t_ul = strtoul(argv[2], &end_t, 10);
    if (errno != 0 || end_t == argv[2] || *end_t != '\0' || t_ul == 0) {
        fprintf(stderr, "Invalid threads_count: %s\n", argv[2]);
        return 1;
    }

    size_t n = (size_t)n_ul;
    size_t threads = (size_t)t_ul;
    if (threads > n) {
        threads = n;
    }

    int *base = malloc(n * sizeof(int));
    int *seq = malloc(n * sizeof(int));
    int *par = malloc(n * sizeof(int));
    int *merged = malloc(n * sizeof(int));
    pthread_t *ids = malloc(threads * sizeof(pthread_t));
    sort_task_t *tasks = malloc(threads * sizeof(sort_task_t));
    size_t *starts = malloc(threads * sizeof(size_t));
    size_t *ends = malloc(threads * sizeof(size_t));

    if (base == NULL || seq == NULL || par == NULL || merged == NULL ||
        ids == NULL || tasks == NULL || starts == NULL || ends == NULL) {
        fprintf(stderr, "Memory allocation failed\n");
        free(base);
        free(seq);
        free(par);
        free(merged);
        free(ids);
        free(tasks);
        free(starts);
        free(ends);
        return 1;
    }

    fill_random(base, n, (unsigned int)time(NULL));
    memcpy(seq, base, n * sizeof(int));
    memcpy(par, base, n * sizeof(int));

    struct timespec t1 = {0}, t2 = {0}, t3 = {0}, t4 = {0};

    clock_gettime(CLOCK_MONOTONIC, &t1);
    qsort(seq, n, sizeof(int), int_cmp);
    clock_gettime(CLOCK_MONOTONIC, &t2);

    size_t chunk = n / threads;
    size_t rem = n % threads;
    size_t pos = 0;
    for (size_t i = 0; i < threads; ++i) {
        size_t len = chunk + (i < rem ? 1 : 0);
        starts[i] = pos;
        ends[i] = pos + len;
        tasks[i].arr = par;
        tasks[i].left = starts[i];
        tasks[i].right = ends[i];
        pos += len;
    }

    clock_gettime(CLOCK_MONOTONIC, &t3);
    for (size_t i = 0; i < threads; ++i) {
        if (pthread_create(&ids[i], NULL, thread_sort, &tasks[i]) != 0) {
            fprintf(stderr, "pthread_create failed for thread %zu\n", i);
            free(base);
            free(seq);
            free(par);
            free(merged);
            free(ids);
            free(tasks);
            free(starts);
            free(ends);
            return 1;
        }
    }
    for (size_t i = 0; i < threads; ++i) {
        pthread_join(ids[i], NULL);
    }
    if (merge_sorted_chunks(par, merged, starts, ends, threads) != 0) {
        fprintf(stderr, "Merge failed\n");
        free(base);
        free(seq);
        free(par);
        free(merged);
        free(ids);
        free(tasks);
        free(starts);
        free(ends);
        return 1;
    }
    clock_gettime(CLOCK_MONOTONIC, &t4);

    int ok_seq = is_sorted(seq, n);
    int ok_par = is_sorted(merged, n);

    printf("=== Multithreaded sort demo (pthread) ===\n");
    printf("Array size        : %zu\n", n);
    printf("Threads requested : %zu\n", (size_t)t_ul);
    printf("Threads used      : %zu\n", threads);
    printf("Sequential sorted : %s\n", ok_seq ? "YES" : "NO");
    printf("Parallel sorted   : %s\n", ok_par ? "YES" : "NO");
    printf("Sequential time   : %llu ms\n", (unsigned long long)elapsed_ms(&t1, &t2));
    printf("Parallel+merge    : %llu ms\n", (unsigned long long)elapsed_ms(&t3, &t4));

    free(base);
    free(seq);
    free(par);
    free(merged);
    free(ids);
    free(tasks);
    free(starts);
    free(ends);
    return (ok_seq && ok_par) ? 0 : 2;
}

