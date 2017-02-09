using Base.Test

str = ""
cred = read(IOBuffer(str), Credential)
@test cred == Credential()
buf = IOBuffer(); write(buf, cred)
@test readstring(seekstart(buf)) == str

str = """
protocol=https
host=example.com
username=alice
password=xxxxx
"""
cred = read(IOBuffer(str), Credential)
@test cred == Credential("https", "example.com", "", "alice", "xxxxx")
buf = IOBuffer(); write(buf, cred)
@test readstring(seekstart(buf)) == str

str = """
host=example.com
password=bar
url=https://a@b/c
username=foo
"""
cred = read(IOBuffer(str), Credential)
@test cred == Credential("https", "b", "/c", "foo", "bar")
buf = IOBuffer(); write(buf, cred)
@test readstring(seekstart(buf)) == """
protocol=https
host=b
path=/c
username=foo
password=bar
"""
