test_that("new_substream does not touch the main .Random.seed", {
  set.seed(999); before <- .Random.seed
  jit <- new_substream(20100715, 7); invisible(jit$draw(function() rnorm(5)))
  expect_identical(before, .Random.seed)
})

test_that("jitter stream is reproducible per (seed, subj) and varies across subj", {
  a <- new_substream(42, 3)$draw(function() runif(3))
  b <- new_substream(42, 3)$draw(function() runif(3))
  c3 <- new_substream(42, 4)$draw(function() runif(3))
  expect_identical(a, b)
  expect_false(identical(a, c3))
})

test_that("jitter draws between main draws do not shift the main stream (the load-bearing invariant)", {
  set.seed(123); ref <- c(runif(1), runif(1))
  set.seed(123); y1 <- runif(1)
  invisible(new_substream(123, 1)$draw(function() { runif(10); rnorm(4) }))
  expect_identical(ref, c(y1, runif(1)))
})

test_that("np_integers is half-open [low, high)", {
  set.seed(1); v <- vapply(1:500, function(i) np_integers(0L, 3L), numeric(1))
  expect_true(all(v %in% c(0, 1, 2)))
})
