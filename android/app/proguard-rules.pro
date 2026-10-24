# Commons Compress registers these ZIP extra-field implementations using
# Class.newInstance(). Keep their constructors available after R8 shrinking.
-keep class org.apache.commons.compress.archivers.zip.** implements org.apache.commons.compress.archivers.zip.ZipExtraField { *; }
