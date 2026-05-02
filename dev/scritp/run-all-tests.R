devtools::load_all(".", quiet = TRUE)
res <- testthat::test_dir("tests/testthat", reporter = "minimal")
print(res)
